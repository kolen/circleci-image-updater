# frozen_string_literal: true

require "rugged"
require_relative "logging"

class RepoUpdater
  include Logging
  attr_accessor :repo

  def initialize(repo_path, token_username:, token:)
    @repo_path = repo_path
    @repo = Rugged::Repository.discover(repo_path)
    @token_username = token_username
    @token = token
  end

  def original_config_content
    repo.lookup(
      master_tree.path(".circleci/config.yml")[:oid]
    ).content
  end

  def master_tree
    master.target.tree
  end

  def master
    repo.branches["origin/master"]
  end

  def create_file(content)
    repo.write content, :blob
  end

  def replace_file_in_tree(blob_oid)
    builder = master_tree
    builder.update [action: :upsert,
                    oid: blob_oid,
                    filemode: 0100644,
                    path: ".circleci/config.yml"]
  end

  def create_commit(tree)
    logger.debug "Creating commit for #{tree.inspect}"
    Rugged::Commit.create(
      repo,
      tree: tree,
      committer: { email: "noreply@digit.az", name: "Docker image update bot", time: Time.now },
      message: "Update image",
      parents: [ master.target ]
    )
  end

  def create_branch(name, commit)
    logger.debug "Creating branch #{name.inspect} @ #{commit.inspect}"
    repo.branches.create name, commit
  end

  def fetch(url)
    remote = repo.remotes.create_anonymous url
    remote.fetch(
      "+refs/heads/master:refs/remotes/origin/master",
      credentials: Rugged::Credentials::UserPassword.new(
        username: @token_username,
        password: @token
      ),
      update_tips: proc do |refname, old_oid, new_oid|
        logger.info "#{repo_path} Update ref #{refname} #{old_oid} -> #{new_oid}"
      end,
      transfer_progress: proc do |text|
        logger.debug "#{repo_path} Transfer: #{text}"
      end
    )
  end
end
