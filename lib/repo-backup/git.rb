require 'tempfile'

# Wrap git, so we can use a custom SSH key
class RepoBackup
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
    origpwd = File.realpath(Dir.pwd)
    begin
      Dir.chdir(opts[:dir]) if opts[:dir]
      system('git', *args, params)
    ensure
      Dir.chdir(origpwd)
    end
  end

  # Check if a repo exists
  def check_remote(uri)
    return run(['ls-remote', '-h', uri], :quiet => true)
  end
end
end
