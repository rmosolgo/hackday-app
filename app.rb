require "sinatra"
require "json"
require "sinatra/reloader" if development?
require "./client"

$webhooks = []

get "/" do
  erb :home
end

post "/github/webhook" do
  request_body = request.body.read
  $webhooks << request_body
  data = JSON.parse(request_body)
  if data["action"] == "created"
    repo = data["repository"]["full_name"]
    pr_branch = data["pull_request"]["head"]
    parent_branch_name = pr_branch["ref"] # does _not_ have `heads/`
    parent_sha = pr_branch["sha"]
    client = Client.new(repo: repo)
    client.add_file(parent_branch_name, parent_sha)
  end
  "OK"
end
