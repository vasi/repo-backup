#!/usr/bin/ruby
require 'yaml'
require 'json'
require 'pathname'
require 'net/http'
require 'pp'

class Client < Struct.new(:base_uri, :token, :name, :parent)
  class Repo
    def initialize(dir, data)
      @data = data
      @dir = dir + name
    end

    def name; @data['name']; end

    def backup
      puts "Backing up #@dir"
      @dir.mkpath

      backup_git
      backup_extras

      exit # FIXME
    end

    def backup_extras; end
    def backup_git
      ENV['GIT_SSH'] = Pathname.pwd.join('sshwrap.sh').realpath.to_s
      out = @dir + 'repo.git'
      if out.exist?
        system('git', '-C', out.to_s, 'remote', 'update')
      else
        system('git', 'clone', '--mirror', ssh_uri, out.to_s)
      end
    end
  end

  def self.create(user, parent)
    klass = case user['type']
      when 'github' then GitHub
      when 'gitlab' then GitLab
    end or raise "Don't know about type #{type}"
    klass.new(user['token'], user['id'], parent)
  end

  def initialize(*args)
    super
    @dir = Pathname.new(parent) + name
  end

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

  def get(path)
    return fetch(File.join(base_uri, path))
  end

  def headers; []; end

  def repos
    repo_data.map { |r| self.class.const_get(:Repo).new(@dir, r) }
  end

  def backup
    repos.each { |r| r.backup }
  end
end

class GitHub < Client
  BaseURI = 'https://api.github.com'
  def initialize(*args)
    super(BaseURI, *args)
  end

  class Repo < Client::Repo
    def ssh_uri; @data['ssh_url']; end
  end

  def headers
    { 'Authorization' => "token #{token}" }
  end

  def repo_data
    orgs = get('/user/orgs').map { |o| o['login'] }
    return orgs.map { |o| get("/orgs/#{o}/repos") }.flatten(1)
  end
end

class GitLab < Client
  BaseURI = 'http://gitlab.com/api/v3'
  def initialize(*args)
    super(BaseURI, *args)
  end

  class Repo < Client::Repo
    def ssh_uri; @data['ssh_url_to_repo']; end
  end

  def headers
    { 'PRIVATE-TOKEN' => token }
  end

  def repo_data
    return get('/projects')
  end
end

BackupDir = 'backup'
config = YAML.load(open('config.yaml'))
config.each { |user| Client.create(user, BackupDir).backup }
