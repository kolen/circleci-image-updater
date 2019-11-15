# frozen_string_literal: true

require "json"

class PRTracker
  def initialize
    if File.exists? filename
      @data = JSON.parse(File.open(filename))
    else
      @data = {}
    end
  end

  def save
    File.open(filename, "w") do |f|
      f.write(JSON.pretty_generate(@data))
    end
  end

  def pr_for_repo(repo_id)
    @data[repo_id]
  end

  def set_pr_for_repo(repo_id, pr_number)
    @data[repo_id] = pr_number
    save
  end

  def remove_pr(repo_id)
    @data.delete(repo_id)
    save
  end

  def filename
    "tracked_pull_requests.json"
  end
end
