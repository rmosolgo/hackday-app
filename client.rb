require "net/http"
require "json"
require "jwt"

class Client
  attr_reader :repo, :jwt, :installation_token

  def initialize(repo:)
    @repo = repo
    @jwt = get_jwt
    @installation_token = get_installation_token
  end

  def add_file(parent_branch, parent_sha)
    parent_tree = get_tree(parent_sha)
    new_tree = parent_tree["tree"] + [
      {
        path: "test-#{Time.now.to_i}.rb",
        mode: "100644",
        type: "blob",
        content: "puts 'Hello World'"
      }
    ]
    created_tree = create_tree(parent_sha, new_tree)
    created_commit = create_commit("Add file by API", created_tree["sha"], parent_sha)
    update_branch(parent_branch, created_commit["sha"])
  end

  def get_tree(parent_sha)
    api_request(:get, "repos/#{@repo}/git/trees/#{parent_sha}")
  end

  def create_tree(parent_sha, new_tree)
    api_request(:post, "repos/#{@repo}/git/trees", {
      base_tree: parent_sha,
      tree: new_tree,
    })
  end

  def create_commit(message, tree_sha, parent_sha)
    api_request(:post, "repos/#{@repo}/git/commits", {
      message: message,
      parents: [parent_sha],
      tree: tree_sha,
    })
  end

  def update_branch(branch_name, target_sha)
    ref_name = "heads/#{branch_name}"
    api_request(:patch, "repos/#{@repo}/git/refs/#{ref_name}", {
      sha: target_sha,
    })
  end

  REQ_CLASS = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }

  # @return Hash<String => Object>
  def api_request(method, path, jwt: nil, **params)
    req_class = REQ_CLASS.fetch(method)
    uri = URI("https://api.github.com/#{path}")
    response = nil

    http_log "#{req_class} => #{uri.inspect}"
    req = req_class.new(uri)
    if params.any?
      http_log "JSON keys: #{params.keys.inspect}"
      req.body = JSON.dump(params)
    end

    # HEADERS:
    # Preview for integration auth
    req["Accept"] = "application/vnd.github.machine-man-preview.v3+json"
    # Auth
    if jwt
      req["Authorization"] = "Bearer #{@jwt}"
    else
      req["Authorization"] = "Bearer #{@installation_token}"
    end

    http_log "headers: #{req.to_hash}"
    response = Net::HTTP.start(uri.host, uri.port, {use_ssl: true}) do |http|
      http_log "begin request"
      http.request(req)
    end
    http_log "response code: #{response.code}"
    http_log "response body: #{response.body}"

    if response.code >= "300"
      raise "HTTP failure: #{response.code}, #{response.body}"
    end

    JSON.parse(response.body)
  end

  private

  PRIVATE_PEM = ENV["PRIVATE_PEM"] || File.read("./hackday-app.2018-01-25.private-key.pem")
  PRIVATE_KEY = OpenSSL::PKey::RSA.new(PRIVATE_PEM)

  def get_jwt
    # Generate the JWT
    payload = {
      # issued at time
      iat: Time.now.to_i,
      # JWT expiration time (10 minute maximum)
      exp: Time.now.to_i + (10 * 60),
      # GitHub App's identifier
      iss: 8501,
    }
    JWT.encode(payload, PRIVATE_KEY, "RS256")
  end

  $installation_ids = {}
  $installation_tokens = {}

  def get_installation_token
    repo_owner = @repo.split("/").first
    $installation_tokens[repo_owner] ||= begin
      # refetch
      installations = api_request(:get, "app/installations", jwt: true)
      installations.each do |inst|
        owner = inst["account"]["login"]
        id = inst["id"]
        $installation_ids[owner] = id
      end
      # Get a token for this owner
      inst_id = $installation_ids.fetch(repo_owner)
      token_res = api_request(:post, "installations/#{inst_id}/access_tokens", jwt: true)
      token_res["token"]
    end
  end

  def log(str)
    puts "[HTTP] #{str}"
  end
end
