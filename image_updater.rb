# frozen_string_literal: true

require "toml"
require_relative "repo_updater"
require_relative "docker_api"
require_relative "logging"
require_relative "github_api"
require_relative "pr_tracker"

# Applies edits to .circleci/config.yml
class ConfigPatcher
  def initialize(content, repo_pattern: nil)
    @original_content = content
    @repo_pattern = repo_pattern || "\w+/\w+"
  end

  def docker_repo
    original_match[1]
  end

  def docker_tag
    original_match[2]
  end

  def original_hash
    original_match[3]
  end

  def patched(new_hash)
    @original_content.gsub(
      /(^\s*- image: #{@repo_pattern}:[0-9a-zA-z_.-]+)(@sha256:\w+)?(?=\s*$)/,
      "\\1@#{new_hash}"
    )
  end

  private

  def original_match
    # it's ok to parse yaml with regex as we're going to modify it
    # with regexes later
    @original_match ||= @original_content.match(
      /^\s*- image: (#{@repo_pattern}):([0-9a-zA-z_.-]+)(?:@(sha256:\w+))?\s*$/
    )
  end
end

class ImageUpdater
  include Logging

  def initialize
    @config = TOML.load_file("image_updater.toml")
  end

  def run_for_repo(repo_name)
    config_repo = @config["repos"][repo_name]
    logger.info "Running for repo #{repo_name}"
    github_id = config_repo["url"].match(%r{https://github.com/(\w+/\w+)\.git})[1]

    github_client = GithubAPIClient.new(
      repo: github_id,
      username: @config["github"]["username"],
      token: @config["github"]["token"]
    )

    pr_tracker = PRTracker.new
    pr_id = pr_tracker.pr_for_repo(github_id)
    if pr_id && github_client.pull_request_open?(pr_id)
      logger.info "PR #{github_id}##{pr_id} is still open, skipping"
      return
    end

    repo = RepoUpdater.new(
      config_repo["dir"],
      token_username: @config["github"]["username"],
      token: @config["github"]["token"],
      committer: config_repo["committer"] || @config["committer"]
    )

    logger.info "Fetching latest origin/master reference"
    repo.fetch config_repo["url"]

    patcher = ConfigPatcher.new repo.original_config_content,
                                repo_pattern: config_repo["repo_pattern"]

    logger.debug "Repo: #{patcher.docker_repo.inspect} tag: #{patcher.docker_tag.inspect}"
    logger.debug "Original hash: #{patcher.original_hash.inspect}"

    docker_api = DockerAPIClient.new patcher.docker_repo
    latest_hash = docker_api.latest_hash patcher.docker_tag
    logger.debug "Latest hash: #{latest_hash.inspect}"
    unless latest_hash.match /sha256:\w+/
      raise "Invalid latest_hash received: #{latest_hash}"
    end

    if patcher.original_hash == latest_hash
      logger.info "Hash unchanged"
      return
    end

    # TODO: return if version is either blacklisted or unverified and
    # current repo is configured to allow only verified versions

    logger.info "Updating .circleci/config.yml"

    new_config = patcher.patched(latest_hash)

    branch_name = "ci-image-update-#{latest_hash[7..14]}"
    if repo.repo.branches[branch_name]
      logger.info "Branch #{branch_name} already exists, skipping"
      return
    end

    new_config_oid = repo.create_file new_config
    logger.debug "New config oid: #{new_config_oid.inspect}"
    updated_tree = repo.replace_file_in_tree new_config_oid
    logger.debug "New tree oid: #{updated_tree.inspect}"
    commit = repo.create_commit updated_tree, hash: latest_hash
    logger.debug "Creating branch #{branch_name.inspect}"
    repo.create_branch branch_name, commit

    logger.debug "Pushing branch #{branch_name.inspect}"
    repo.push config_repo["url"], branch_name

    logger.debug "Creating PR for #{branch_name.inspect}"
    github_client.create_pull_request hash: latest_hash,
                                      branch: branch_name
  end

  def run
    @config["repos"].each_key do |repo_name|
      run_for_repo repo_name
    end
  end
end

if __FILE__ == $0
  Logging.logger.level = Logger::DEBUG
  updater = ImageUpdater.new
  updater.run
end
