require "sinatra"
require "thin"
require "sinatra/reloader" if development?

$webhooks = []

get "/" do
  erb :home
end

post "/github/webhook" do
  $webhooks << request.body
  "OK"
end
