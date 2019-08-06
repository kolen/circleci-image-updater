# frozen_string_literal: true

require "json"

class PRTracker
  def initialize
    @data = JSON.parse(File.open(filename))
  end

  def save
    JSON.dump(@data, File.open(filename, "w"))
  end

  def pr_for_repo(repo_id)
    @data[repo_id]
  end

  def remove_pr(repo_id)
    @data.delete(repo_id)
  end

  def filename
    "tracked_pull_requests.json"
  end
end
