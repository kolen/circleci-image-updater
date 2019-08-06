# frozen_string_literal: true

require "faraday"
require "faraday_middleware"

class GithubAPIClient
  include Logging

  def initialize(repo:, username:, token:)
    @repo = repo
    @username = username
    @token = token
  end

  def pull_request_open?(id)
    logger.debug "Fetching pull requests status #{@repo}##{id}"
    resp = connection.get "pulls/#{id}"
    logger.debug "PR #{@repo}##{id} is #{resp.body['state']}"
    resp.body["state"] == "open"
  end

  def create_pull_request(hash:, branch:)
    logger.info "Creating PR for #{branch} (#{@repo})"
    resp = connection.post(
      "pulls",
      title: "Bump CI docker image to #{hash[7..14]}",
      head: branch,
      base: "master",
      maintainer_can_modify: true,
      body: pull_request_body(hash)
    )
    logger.info "Created PR #{resp['html_url']}"
    resp["id"]
  end

  private

  def pull_request_body(hash)
    <<~END
      Update main docker image on CircleCI to `#{hash}`.

      This is automated pull request.
    END
  end

  def connection
    @connection ||= Faraday.new "https://api.github.com/repos/#{@repo}/" do |conn|
      conn.basic_auth @username, @token
      conn.request :json
      conn.response :raise_error
      conn.response :json
      conn.adapter :net_http
    end
  end
end
