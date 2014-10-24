#!/usr/bin/ruby
require 'yaml'
require 'json'
require 'pathname'
require 'tempfile'
require 'net/http'
require 'pp'

# Wrap git, so we can use a custom SSH key
class Git < Struct.new(:dir, :private_key)
  def keypath
    File.realpath(private_key)
  end

  # Setup a wrapper, if it doesn't already exist
  def ssh_wrap
    return if !private_key
    unless @wrapper
      @wrapper = Tempfile.new(['.sshwrap', '.sh'], dir)
      @wrapper.chmod(0500) # read/execute
      @wrapper.write <<-EOF
#!/bin/sh
exec ssh -i #{keypath} "$@"
EOF
      @wrapper.close
    end
    ENV['GIT_SSH'] = File.realpath(@wrapper.path)
  end

  def run(*args)
    ssh_wrap
    system('git', *args)
  end
end

# A source of repos to backup
class Source < Struct.new(:backup, :spec)
  # A repo to be backed up
  class Repo < Struct.new(:source, :spec)
    RepoName = 'repo.git'

    def name; spec['name']; end

    # Should be a unique ID for this repo
    def id
      "#{source.name}/#{name}"
    end

    # Where the backup should go
    def dir
      source.dir + name
    end

    # Backup this repo
    def backup
      puts "Backing up #{id}"
      dir.mkpath

      backup_git
      backup_extras

      exit # FIXME
    end

    # Backup the git repository
    def backup_git(uri = nil, out = RepoName)
      uri ||= ssh_uri
      repo = dir + out
      if repo.exist?
        source.git('-C', repo.to_s, 'fetch', '--all', '--quiet')
      else
        source.git('clone', '--mirror', uri, repo.to_s)
      end
    end

    # Fetch a URI, and write the contents to disk
    def save(file, uri)
      data = source.get(uri)
      json = JSON.pretty_generate(data)
      dir.join(file).open('w') { |f| f.puts(json) }
    end
  end

  # Factory for creating sources from a spec
  def self.create(backup, spec)
    type = spec['type']
    klass = case type
      when 'github' then GitHub
      when 'gitlab' then GitLab
    end or raise "Don't know about type #{type}"
    klass.new(backup, spec)
  end

  # The name of this source
  def name; spec['name']; end

  # Where this source's backup should go
  def dir
    backup.dir + name
  end

  # Fetch a full URI, handling redirects
  def fetch(uri)
    uri = URI(uri)
    req = Net::HTTP::Get.new(uri)
    headers.each { |k,v| req[k] = v }

    params = { :use_ssl => uri.scheme == 'https' }
    Net::HTTP.start(uri.hostname, uri.port, params) do |http|
      resp = http.request(req)
      case resp
      when Net::HTTPRedirection then
        fetch(resp['location'])
      when Net::HTTPSuccess then
        return JSON.parse(resp.body)
      else
        raise "Failed to fetch #{uri}: #{resp}"
      end
    end
  end
  private :fetch

  # GET a REST API path
  def get(path)
    return fetch(File.join(base_uri, path))
  end

  # Get a list of repo objects in this source
  def repos
    repo_data.map { |r| self.class.const_get(:Repo).new(self, r) }
  end

  # Forward git commands to backup object
  def git(*args); backup.git(*args); end

  ### SUBCLASS
  # Headers to add to each request
  def headers; []; end
  # Get a spec structure for each repo in this source
  def repo_data; []; end
  class Repo
    # Backup extra things, after the git repo itself
    def backup_extras; end
    # Get the ssh URI for this repo
    def ssh_uri; end
  end
end

class GitHub < Source
  def base_uri
    'https://api.github.com'
  end
  def headers
    { 'Authorization' => "token #{spec['token']}" }
  end

  class Repo < Source::Repo
    WikiName = 'wiki.git'

    def ssh_uri; spec['ssh_url']; end
    def fullname; spec['full_name']; end

    def save(file, path)
      super(file, "repos/#{fullname}/#{path}")
    end

    def backup_wiki
      return unless spec['has_wiki']
      uri = ssh_uri.sub(/(\.git)$/, '.wiki\1')
      backup_git(uri, WikiName)
    end

    def backup_extras
      backup_wiki
      save('issues', 'issues')
      save('issues-comments', 'issues/comments')
    end
  end

  def repo_data
    orgs = get('/user/orgs').map { |o| o['login'] }
    return orgs.map { |o| get("/orgs/#{o}/repos") }.flatten(1)
  end
end

class GitLab < Source
  def base_uri
    'http://gitlab.com/api/v3'
  end
  def headers
    { 'PRIVATE-TOKEN' => spec['token'] }
  end

  class Repo < Source::Repo
    def ssh_uri; spec['ssh_url_to_repo']; end
  end

  def repo_data
    return get('/projects')
  end
end

# A manager for the backup process
class RepoBackup
  attr_reader :dir, :config

  def initialize(**opts)
    @dir = Pathname.new(opts[:outdir])
    @config = open(opts[:config]) { |f| YAML.load(f) }
    @git = Git.new(@dir, opts[:private_key])
  end

  # Run git
  def git(*args); @git.run(*args); end

  # Get all sources
  def sources
    @config.map { |spec| Source.create(self, spec) }
  end

  # Get all repos
  def repos
    sources.map { |src| src.repos }.flatten(1)
  end

  # Do a backup
  def backup
    repos.each { |r| r.backup }
  end
end


RepoBackup.new(
  outdir: 'backup',
  config: 'config.yaml',
  private_key: 'key'
).backup
