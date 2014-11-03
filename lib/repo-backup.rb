require 'repo-backup/git'
require 'repo-backup/source'

require 'yaml'
require 'pathname'

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
