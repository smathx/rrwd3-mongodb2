class Photo
    
  # Photos Collection ---------------------------------------------------------
    
  def self.mongo_client
    Mongoid::Clients.default
  end
  
  attr_accessor :id, :location
  attr_writer :contents

  def initialize(params={})
    if params[:_id]
      @id = params[:_id].to_s
    end
    
    if params[:metadata]
      @location = Point.new(params[:metadata][:location])
    end
  end
  
  def persisted?
    !@id.nil?
  end
  
  def save
    if !persisted? and @contents
      
      gps = EXIFR::JPEG.new(@contents).gps
      @contents.rewind
      
      @location = Point.new(:lng => gps.longitude, :lat => gps.latitude)
      
      description = {}
      description[:content_type] = "image/jpeg"
      
      description[:metadata] = {}
      description[:metadata][:location] = @location.to_hash

      grid_file = Mongo::Grid::File.new(@contents.read, description)
      _id = self.class.mongo_client.database.fs.insert_one(grid_file)
      
      @id = _id.to_s
    end
    
    return @id
  end
  
  # TODO: limit(nil) is nil so use big number for now.
  def self.all(offset=0, limit=9999999)
    photos = []
    mongo_client.database.fs.find.skip(offset).limit(limit).each do |item| 
      photos << Photo.new(item) 
    end
    return photos
  end
  
  def self.find(string_id)
    bson_id = BSON::ObjectId.from_string(string_id)
    file = mongo_client.database.fs.find(:_id => bson_id).first
    return file ? Photo.new(file): nil
  end
  
  def contents
    bson_id = BSON::ObjectId.from_string(@id)
    file = self.class.mongo_client.database.fs.find_one(:_id => bson_id)
    
    if file 
      buffer = ""
      file.chunks.reduce([]) do |x,chunk| 
        buffer << chunk.data.data 
      end
      return buffer
    end 
  end
  
  def destroy
    bson_id = BSON::ObjectId.from_string(@id)
    self.class.mongo_client.database.fs.delete(bson_id)
  end
  
end
