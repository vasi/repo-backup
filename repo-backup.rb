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

  def run(args, opts = {})
    params = {}
    params.merge!({out: :close, err: :close}) if opts[:quiet]

    ssh_wrap
    system('git', *args, params)
  end

  # Check if a repo exists
  def check_remote(uri)
    return run(['ls-remote', '-h', uri], :quiet => true)
  end
end

# A source of repos to backup
class Source < Struct.new(:backup, :spec)
  # A repo to be backed up
  class Repo < Struct.new(:source, :spec)
    RepoName = 'repo.git'

    def name; spec['name']; end
    def git; source.git; end

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
      dir.mkpath
      save('spec.json', spec)
      backup_git
      backup_extras
    end

    # Backup the git repository
    def backup_git(uri = nil, dest = nil)
      uri ||= ssh_uri
      dest ||= dir + RepoName

      if dest.exist?
        git.run(['-C', dest.to_s, 'fetch', '--all', '--quiet'])
      else
        git.run(['clone', '--mirror', uri, dest.to_s])
      end
    end

    # Write some data to disk
    def save(file, data)
      data = JSON.pretty_generate(data) unless String === data
      dir.join(file).open('w') { |f| f.puts(data) }
    end

    # Fetch a URI, and write the contents to disk
    def fetch(file, uri)
      save(file, source.get(uri))
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

  # Forward git
  def git; backup.git; end

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
    repo_data.map { |r| self.class.const_get(:Repo).new(self, r) }.
      sort_by(&:name)
  end

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

    def fetch(file, path)
      super(file, "repos/#{fullname}/#{path}")
    end

    def backup_wiki
      return unless spec['has_wiki']

      # Sometimes the wiki is turned on, but uninitialized
      # Check if repo exists
      dest = dir + WikiName
      uri = ssh_uri.sub(/(\.git)$/, '.wiki\1')
      if dest.exist? || git.check_remote(uri)
        backup_git(uri, dest)
      end
    end

    def backup_extras
      backup_wiki
      fetch('issues.json', 'issues')
      fetch('issues-comments.json', 'issues/comments')
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
    def name; spec['path']; end
  end

  def repo_data
    return get('/projects')
  end
end

# A manager for the backup process
class RepoBackup
  attr_reader :dir, :config, :git

  def self.log(msg)
    msg = "\033[1m" + msg + "\033[0m" if $stdout.isatty
    puts msg
  end

  def initialize(opts)
    @dir = Pathname.new(opts[:outdir])
    @config = open(opts[:config]) { |f| YAML.load(f) }
    @git = Git.new(@dir, opts[:private_key])
  end

  # Get all sources
  def sources
    @config.map { |spec| Source.create(self, spec) }
  end

  # Get all repos
  def repos
    sources.map { |src| src.repos }.flatten(1)
  end

  # Ensure we're locked
  def lock(&block)
    dir.mkpath
    lockfile = dir.join('lock')
    lockfile.open('w') do |f|
      unless f.flock(File::LOCK_EX | File::LOCK_NB)
        puts "repo-backup is already running!"
        exit(1)
      end

      begin
        block.()
      ensure
        lockfile.unlink
      end
    end
  end
  private :lock

  # Do a backup
  def backup
    lock do
      RepoBackup.log "Fetching repo info"
      repos.each do |repo|
        RepoBackup.log "Backing up #{repo.id}"
        repo.backup
      end
    end
    RepoBackup.log "Complete!"
  end
end

config, key, outdir = *ARGV
RepoBackup.new(
  outdir: outdir,
  config: config,
  private_key: key
).backup
