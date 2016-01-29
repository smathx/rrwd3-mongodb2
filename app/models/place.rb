class Place
    
  attr_accessor :id, :formatted_address, :location, :address_components
    
  def self.mongo_client
    Mongoid::Clients.default
  end
  
  def self.collection
    self.mongo_client[:places]
  end
  
  def self.load_all(file) 
    collection.insert_many(JSON.parse(file.read))
  end

  def self.find_by_short_name(search)
    collection.find(:"address_components.short_name" => search)
  end
  
  def self.to_places(view)
    places = []
    view.each { |x| places << Place.new(x) }
    return places
  end

  def self.find(string_id)
    bson_id = BSON::ObjectId.from_string(string_id)
    result = collection.find(:_id=>bson_id).first
    if result
      return Place.new(result)
    end  
  end

  def self.all(offset=0, limit=nil)
    if limit
      to_places collection.find.skip(offset).limit(limit)
    else
      to_places collection.find.skip(offset)
    end
  end

  def initialize(params)
    @id = params[:_id].to_s
    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
    
    @address_components = []
    params[:address_components].each do |a|
      @address_components << AddressComponent.new(a)
    end
  end
  
  def destroy
    self.class.collection.delete_one(:_id=>BSON::ObjectId.from_string(@id))
  end
end
