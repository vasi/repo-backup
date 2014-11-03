require 'net/http'

# A source of repos to backup
class RepoBackup
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
        git.run(['fetch', '--all', '--quiet'], :dir => dest)
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
    req = Net::HTTP::Get.new(uri.to_s)
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
end

require 'repo-backup/source/github'
require 'repo-backup/source/gitlab'
