#!/usr/bin/ruby
if __FILE__ == $0
  $LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
end

require 'repo-backup'

config, key, outdir = *ARGV
RepoBackup.new(
  outdir: outdir,
  config: config,
  private_key: key.empty? ? nil : key
).backup
