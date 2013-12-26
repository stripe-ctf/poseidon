require 'etc'

class Poseidon::SSHStrategy
  include Chalk::Log

  def initialize(valid_gid=nil)
    @valid_gid = valid_gid
  end

  def interpret(fds, args)
    interpret_args(args)
    interpret_fds(fds)
  end

  private

  def interpret_args(args)
    log.info('Calling with args', args: args)

    command = args.shift

    env_updates = {}
    while true
      unless variable = args.shift
        raise "Environment list did not end with a --"
      end

      break if variable == '--'

      key, value = variable.split("=")
      unless key && value
        raise "Invalid environment key=value: #{variable.inspect}"
      end

      env_updates[key] = value
    end

    $0 = "Poseidon slave: #{command}"
    ARGV.clear
    ARGV.concat(args)
    apply_env_updates(env_updates)
  end

  def interpret_fds(fds)
    stdin, stdout, stderr = fds

    $stdin.reopen(stdin)
    $stdout.reopen(stdout)
    $stderr.reopen(stderr)

    stdin.close
    stdout.close
    stderr.close
  end

  def apply_env_updates(env_updates)
    ENV.update(env_updates)

    # TODO: figure out how to authenticate this.
    if username = env_updates['USER']
      passwd = Etc.getpwnam(username)
      uid = passwd.uid
      gid = passwd.gid

      sanity_check(uid, gid)
      drop_privileges(username, uid, gid)

      ENV['HOME'] = passwd.dir unless env_updates.include?('HOME')
      Dir.chdir(ENV['HOME'])
    end
  end

  def drop_privileges(username, uid, gid)
    Process.initgroups(username, gid)
    Process::Sys.setgid(gid)
    Process::Sys.setuid(uid)
    # Be paranoid and make sure we actually dropped
    begin
      Process::Sys.setuid(0)
    rescue Errno::EPERM
    else
      log.error("XXX: Did not drop permissions!")
      # Did not successfully drop permissions. Panic!
      exit!(1)
    end
  end

  def sanity_check(uid, gid)
    if uid == 0
      log.error('XXX: Trying to become root')
      exit!(1)
    elsif @valid_gid && gid != @valid_gid
      log.error('XXX: Trying to become invalid group', gid: gid, uid: uid, valid_gid: @valid_gid)
      exit!(1)
    end
  end
end
