#!/usr/bin/ruby
require 'yaml'
require 'json'
require 'net/http'
require 'pp'

class RestClient
  def initialize(base_uri)
    @base_uri = base_uri
  end

  def self.create(type, token)
    klass = case type
      when 'github' then GitHub
      when 'gitlab' then GitLab
    end or raise "Don't know about type #{type}"
    klass.new(token)
  end

  def headers; []; end

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
        raise "Failed to fetch #{path}: #{resp}"
      end
    end
  end

  def get(path)
    return fetch(File.join(@base_uri, path))
  end

  def repos
    repo_data.map { |r| self.class.const_get(:Repo).new(r) }
  end
end

class GitHub < RestClient
  BaseURI = 'https://api.github.com'

  class Repo < Struct.new(:data)
    def name; data['name']; end
    def ssh_uri; data['ssh_url']; end
  end

  def initialize(token)
    @token = token
    super(BaseURI)
  end

  def headers
    { 'Authorization' => "token #@token" }
  end

  def repo_data
    orgs = get('/user/orgs').map { |o| o['login'] }
    return orgs.map { |o| get("/orgs/#{o}/repos") }.flatten(1)
  end
end

class GitLab < RestClient
  BaseURI = 'http://gitlab.com/api/v3'

  class Repo < Struct.new(:data)
    def name; data['name']; end
    def ssh_uri; data['ssh_url_to_repo']; end
  end

  def initialize(token)
    @token = token
    super(BaseURI)
  end

  def headers
    { 'PRIVATE-TOKEN' => @token }
  end

  def repo_data
    return get('/projects')
  end
end

config = YAML.load(open('config.yaml'))
config.each do |user|
  id = user['id']
  client = RestClient.create(user['type'], user['token'])
  pp client.repos.map { |r| r.ssh_uri }
end
