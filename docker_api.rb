# frozen_string_literal: true

require "faraday"
require "faraday_middleware"
require "json"

class DockerAPIClient
  def initialize(repo)
    @repo = repo
  end

  def latest_hash(tag)
    resp = connection.head "#{@repo}/manifests/#{tag}" do |req|
      req.headers["Accept"] = "application/vnd.docker.distribution.manifest.v2+json"
    end
    resp.headers["Docker-Content-Digest"]
  end

  private

  def token
    @token ||= token_new
  end

  def token_new
    connection = Faraday.new do |conn|
      conn.response :raise_error
      conn.response :json
      conn.adapter :net_http
    end
    resp = connection.get "https://auth.docker.io/token?service=registry.docker.io&scope=repository:#{@repo}:pull"
    resp.body["access_token"]
  end

  def connection
    Faraday.new "https://registry.hub.docker.com/v2/" do |conn|
      conn.request :oauth2, token, token_type: :bearer
      conn.response :raise_error
      conn.response :json
      conn.adapter :net_http
    end
  end
end
