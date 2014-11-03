class RepoBackup
class Source
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
end
end
