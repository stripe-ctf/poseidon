require 'etc'

class Poseidon::SSHStrategy
  include Chalk::Log

  def initialize(opts={})
    @valid_gid = opts[:valid_gid]
    @slave_name = opts[:slave_name] || 'poseidon slave'
    @logfile_selector = opts[:logfile_selector]
  end

  def interpret(identity, fds, args)
    command, args, pwd, env_updates = interpret_args(args)

    change_to_logfile(env_updates)
    apply_settings(command, args, pwd, env_updates)
    interpret_fds(fds)

    command
  end

  private

  def interpret_args(args)
    log.info('Calling with args', args: args)

    command = args.shift

    pwd = nil
    env_updates = {}
    while true
      unless variable = args.shift
        raise "Environment list did not end with a --"
      end

      case variable
      when '--'
        break
      when /\A--(\w+)=(.*)\z/
        type = $1
        value = $2
        case type
        when 'env'
          env_key, env_value = value.split("=")
          unless env_key && env_value
            raise "Invalid environment key=value: #{value.inspect}"
          end
          env_updates[env_key] = env_value
        when 'pwd'
          pwd = value
        else
          raise "Unrecognized directive type #{type.inspect}"
        end
      else
        raise "Positional argument found before --: #{variable.inspect}"
      end
    end

    [command, args, pwd, env_updates]
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

  def apply_settings(command, args, pwd, env_updates)
    $0 = "#{@slave_name}: #{command}"
    ARGV.clear
    ARGV.concat(args)
    apply_env_updates(env_updates)
    Dir.chdir(pwd) if pwd
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

  def change_to_logfile(env_updates)
    return unless @logfile_selector
    # Note: USER hasn't been validated at this point. Use with care.
    return unless logfile = @logfile_selector.call(env_updates)

    # TODO: create a better interface for this in Chalk::Log
    ::Logging.logger.root.appenders = [
      ::Logging.appenders.file(logfile, layout: Chalk::Log.layout)
    ]
  end
end
