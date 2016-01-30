# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

# Clear photos

  Photo.all.each { |photo| photo.destroy }  
  
# Clear places  
  
  Place.collection.delete_many({})

# Create indexes

  Place.create_indexes
  
# Load place data from JSON file

  json_file="./db/places.json"
  Place.load_all(File.open(json_file))
  
# Load photos and save with nearest place within a mile.
  
  image_spec = './db/image*.jpg'
  
  Dir.glob(image_spec).sort.each { |file_name|
    photo = Photo.new 
    photo.contents = File.open(file_name)
    photo.save
    photo.place = photo.find_nearest_place_id(1 * 1609.34)
    photo.save
  }

