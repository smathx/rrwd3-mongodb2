class Place
  include ActiveModel::Model

  def persisted?
    !@id.nil?
  end
  
  # Wipe out 'places' collection and reload from JSON file. Should return 39.
  def self.reset(json_file="./db/places.json")
    collection.delete_many({})
    result = load_all(File.open(json_file))
    return result.inserted_count
  end
    
  # Places Collection ---------------------------------------------------------
    
  def self.mongo_client
    Mongoid::Clients.default
  end
  
  def self.collection
    self.mongo_client[:places]
  end
  
  def self.load_all(file) 
    collection.insert_many(JSON.parse(file.read))
  end

  attr_accessor :id, :formatted_address, :location, :address_components
  
  def initialize(params)
    @id = params[:_id].to_s
    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
    
    @address_components = []
    
    if params[:address_components]
      params[:address_components].each do |a|
        @address_components << AddressComponent.new(a)
      end
    end
  end
  
  # Standard Queries ----------------------------------------------------------

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
  
  def destroy
    self.class.collection.delete_one(:_id=>BSON::ObjectId.from_string(@id))
  end
  
  # Aggregation Framework Queries ---------------------------------------------
  
  # To get the same output as the notes skip 48 not 200:
  #   pp Place.get_address_components({:_id=>-1},48,3).to_a; nil
  
  def self.get_address_components(sort=nil, offset=nil, limit=nil)
    pipeline = []
    
    pipeline << { :$unwind => "$address_components" }
    pipeline << { :$project => { 
                    :address_components => 1, 
                    :formatted_address => 1, 
                    :"geometry.geolocation" => 1
                  } 
                }
                
    if sort
      pipeline << { :$sort => sort }
    end
    if offset
      pipeline << { :$skip => offset }
    end
    if limit
      pipeline << { :$limit => limit }
    end
              
    collection.find.aggregate(pipeline)
  end

  def self.get_country_names
    pipeline = []
    
    pipeline << { :$project => { 
                   :"address_components.long_name" => 1,
                   :"address_components.types" => 1
                 } 
               }
    pipeline << { :$unwind => "$address_components" }
    pipeline << { :$unwind => "$address_components.types" }
    pipeline << { :$match => { :"address_components.types" => "country" }}
    pipeline << { :$group => { :_id => "$address_components.long_name" } }
    
    collection.find.aggregate(pipeline).to_a.map { |item| item[:_id] }
  end
  
  def self.find_ids_by_country_code(country_code)
    pipeline = []
    
    pipeline << { :$match => { :"address_components.short_name" => country_code }}
    pipeline << { :$project => { :_id => 1 } }

    collection.find.aggregate(pipeline).to_a.map { |item| item[:_id].to_s }
  end
  
  # Geolocation Queries -------------------------------------------------------
  
  def self.create_indexes
    collection.indexes.create_one({:"geometry.geolocation" =>Mongo::Index::GEO2DSPHERE})
  end
  
  def self.remove_indexes
    collection.indexes.drop_one("geometry.geolocation_2dsphere")
  end
  
  def self.near(point, max_meters=nil)
    search_spec = { :$near => { :$geometry => point.to_hash } } 
    
    if max_meters
      search_spec[:$near][:$maxDistance] = max_meters
    end

    collection.find(:"geometry.geolocation" => search_spec)
  end

  def near(max_meters=nil)
    self.class.to_places(self.class.near(@location, max_meters))
  end

  # Relationships -------------------------------------------------------------

  def photos(offset=0, limit=99999999)
    all_photos = []
    
    bson_id = BSON::ObjectId.from_string(@id)
    Photo.mongo_client.database.fs.find(:"metadata.place" => bson_id)
      .skip(offset).limit(limit).each do | item| 
        all_photos << Photo.new(item) 
      end
    return all_photos
  end

end
