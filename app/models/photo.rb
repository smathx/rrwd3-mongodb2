class Photo
  
  # Remove existing photos and reload.
  def self.reset  
    all.each { |photo| photo.destroy }  
    
    (1..6).each { |n|
      photo = Photo.new 
      photo.contents = File.open("./db/image#{n}.jpg")
      photo.save
    }
    return mongo_client.database.fs.find.count
  end
    
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
      @place = params[:metadata][:place]
    end
  end
  
  def persisted?
    !@id.nil?
  end
  
  def save
    if !persisted?
      if @contents
        gps = EXIFR::JPEG.new(@contents).gps
        @contents.rewind
      
        @location = Point.new(:lng => gps.longitude, :lat => gps.latitude)
      
        description = {}
        description[:content_type] = "image/jpeg"
      
        description[:metadata] = {}
        description[:metadata][:location] = @location.to_hash if !@location.nil?
        description[:metadata][:place] = @place

        grid_file = Mongo::Grid::File.new(@contents.read, description)
        _id = self.class.mongo_client.database.fs.insert_one(grid_file)
      
        @id = _id.to_s
      end
    else
      bson_id = BSON::ObjectId.from_string(@id)
      
      description = {}
      description[:metadata] = {}
      description[:metadata][:location] = @location.to_hash if !@location.nil?
      description[:metadata][:place] = @place
      
      self.class.mongo_client.database.fs.find(:_id => bson_id)
        .update_one(:$set => description)
    end
    
    return @id
  end
  
  # TODO: limit(nil) is nil so use big number for now.
  def self.all(offset=0, limit=99999999)
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
  
  # Relationships -------------------------------------------------------------
  
  def find_nearest_place_id(max_meters)
    # near() results are sorted nearest to furthest
    result = Place.near(@location, max_meters).projection(_id: 1).first
    return result ? result[:_id]: nil
  end
  
  def place
    return @place ? Place.find(@place.to_s): nil
  end
  
  # 'thing' may be a String, BSON::ObjectId, or Place object. @place is
  # always a BSON::ObjectId
  def place=(thing)
    @place =  case thing
              when String 
                BSON::ObjectId.from_string(thing)
              when Place 
                BSON::ObjectId.from_string(thing.id)
              when BSON::ObjectId 
                thing
              else
                nil
              end
  end
  
  # 'id' is either a BSON::ObjectId or a String.
  def self.find_photos_for_place(id)
    bson_id = BSON::ObjectId.from_string(id.to_s)
    mongo_client.database.fs.find(:"metadata.place" => bson_id)
  end
  
end
