# frozen_string_literal: true

require "json"

class VersionTracker
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

  def version(hash)
    @data[hash].to_sym
  end

  def set_version(hash, status)
    @data[hash] = status
    save
  end

  def filename
    "known_versions.json"
  end
end
