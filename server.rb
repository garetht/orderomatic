require 'sinatra'
require 'json'
require './fresh_direct'

before do
  content_type :json
end

post '/fresh-direct' do
  fd_array = JSON.parse(request.env["rack.input"].read)
  fresh = FreshDirect.new fd_array
  fresh.get_cookies.to_json
end
