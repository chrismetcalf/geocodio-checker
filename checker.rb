#!/usr/bin/env ruby
#

require 'soda/client'
require 'trollop'
require 'yaml'
require 'csv'
require 'json'
require 'uri'
require 'geo-distance'

# Read defaults from our config file if it's present
config = {}
if File.readable?("#{ENV['HOME']}/.soda.yml")
  config = YAML::load(File.open("#{ENV['HOME']}/.soda.yml")).inject({}){ |memo, (k,v)| memo[k.to_sym] = v; memo}
end

# Options
opts = Trollop::options do
  opt :domain,        "Site domain",                                   :type => :string, :required => true
  opt :uid,           "UID of the dataset to load into",               :type => :string, :required => true
  opt :column,        "Name of the location column",                   :type => :string, :required => true
  opt :username,      "Socrata username/email",                        :type => :string, :default => config[:username]
  opt :password,      "Socrata password",                              :type => :string, :default => config[:password]
  opt :app_token,     "An app token you've registered for your app",   :type => :string, :default => config[:app_token]
  opt :geocodio_key,  "Geocod.io developer key",                       :type => :string, :required => true
end

# Set up our client
client = SODA::Client.new(config.merge(opts))

data = CSV.parse(client.get("/api/views/#{opts[:uid]}/rows.csv"), :headers => true)

# Get just the locations and lat/lons
locations = data.collect { |r| 
  address, lat, lon = r[opts[:column]].match(/^(.*),\s*\(([0-9\-.]+),\s*([0-9\-.]+)\)/)[1..3]

  [address, lat, lon]
}

# Send our locations off to be geocoded
uri = URI.parse("http://api.geocod.io/v1/geocode?api_key=#{opts[:geocodio_key]}")
http = Net::HTTP.new(uri.host, uri.port)
request = Net::HTTP::Post.new(uri.request_uri)
request.content_type = "application/json"
request.body = locations.collect{ |l| l.first }.to_json
response = http.request(request)

if response.code != 200
  STDERR.puts "Error Error!"
  STDERR.puts response.body
end
results = JSON::parse(response.body)["results"]

# Correlate our results with theirs
results.each_index do |i|
  top = results[i]["response"]["results"].first
  locations[i] += [top["formatted_address"], top["accuracy"], top["location"]["lat"], top["location"]["lng"]]

  # Calculate the error
  dist = GeoDistance::Haversine.geo_distance(locations[i][1], locations[i][2], locations[i][5], locations[i][6])
  locations[i] << dist.to_meters
end

puts locations.collect{ |r| r.join("\t") }.join("\n")
