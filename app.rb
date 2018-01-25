require "sinatra"
require "json"
require "sinatra/reloader" if development?
require "./client"
require "./command"

$webhooks = []

get "/" do
  erb :home
end

post "/github/webhook" do
  request_body = request.body.read
  $webhooks << request_body
  data = JSON.parse(request_body)
  if data["action"] == "created"
    comment = data["comment"]
    comment_body = comment["body"]
    if comment_body.start_with?("simon says")
      repo = data["repository"]["full_name"]
      pr_branch = data["pull_request"]["head"]
      parent_branch_name = pr_branch["ref"] # does _not_ have `heads/`
      parent_sha = pr_branch["sha"]
      command = Command.new(comment)
      client = Client.new(repo: repo)
      client.dispatch(command, parent_branch_name, parent_sha)
    end
  end
  "OK"
end
