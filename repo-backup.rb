#!/usr/bin/ruby
if __FILE__ == $0
  $LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
end


require 'pp'
require 'repo-backup/rest-json-client'
client = RepoBackup::RestJsonClient.new('https://api.github.com')
pp client.get('user/orgs')
exit

require 'repo-backup'

config, key, outdir = *ARGV
RepoBackup.new(
  outdir: outdir,
  config: config,
  private_key: key.empty? ? nil : key
).backup
