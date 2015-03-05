class RepoBackup
class Source
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

    def fetch(file, path)
      super(file, "repos/#{name}/#{path}")
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
end
end
