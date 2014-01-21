require 'etc'

class Poseidon::SSHStrategy
  include Chalk::Log

  def initialize(opts={})
    @valid_gids = opts.delete(:valid_gids)
    @slave_name = opts.delete(:slave_name) || 'poseidon slave'
    @logfile_selector = opts.delete(:logfile_selector)

    raise "Unrecognized options: #{opts.keys.inspect}" if opts.length > 0
  end

  def interpret(identity, fds, args)
    username, uid, gid, home = interpret_identity(identity)
    log.info('Caller information', args: args, username: username, uid: uid, gid: gid)
    command, args, pwd, env_updates = interpret_args(args)

    change_to_logfile(username)
    apply_settings(command, args, env_updates)
    apply_pwd(pwd, home)
    apply_fds(fds)
    # This should be last, since once the setuid has happened we can't
    # trust the process anymore.
    apply_identity(username, uid, gid, home)

    command
  end

  private

  def interpret_args(args)
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

  def interpret_identity(identity)
    uid = identity.uid
    gid = identity.gid
    sanity_check(uid, gid)

    passwd = Etc.getpwuid(uid)
    username = passwd.name
    home = passwd.dir

    [username, uid, gid, home]
  end

  def apply_pwd(pwd, home)
    pwd ||= home
    Dir.chdir(pwd)
  end

  def apply_identity(username, uid, gid, home)
    drop_privileges(username, uid, gid)

    ENV['USER'] = username
    ENV['HOME'] = home
  end

  def apply_fds(fds)
    stdin, stdout, stderr = fds

    $stdin.reopen(stdin)
    $stdout.reopen(stdout)
    $stderr.reopen(stderr)

    stdin.close
    stdout.close
    stderr.close
  end

  def apply_settings(command, args, env_updates)
    $0 = "#{@slave_name}: #{command}"
    ARGV.clear
    ARGV.concat(args)
    apply_env_updates(env_updates)
  end

  def apply_env_updates(env_updates)
    ENV.update(env_updates)
  end

  def drop_privileges(username, uid, gid)
    begin
      Process.initgroups(username, gid)
    rescue Errno::EPERM => e
      current_uid = Etc.getpwuid.uid
      raise e unless current_uid

      # Not a huge deal; this means we're not running as root. The one
      # case this could be sketchy is if poseidon is running with an
      # escalated secondary group list, but that seems pretty
      # far-fetched.
      #
      # In the future, we may want to support running Poseidon without
      # the setuid at all.
    end

    Process::Sys.setgid(gid)
    Process::Sys.setuid(uid)

    # Be paranoid and make sure we actually dropped
    return if uid == 0
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
    if @valid_gids && !@valid_gids.include?(gid)
      log.error('XXX: Trying to become invalid group', gid: gid, uid: uid, valid_gids: @valid_gids)
      exit!(1)
    end
  end

  def change_to_logfile(username)
    return unless @logfile_selector
    return unless logfile = @logfile_selector.call(username)

    # TODO: create a better interface for this in Chalk::Log
    ::Logging.logger.root.appenders = [
      ::Logging.appenders.file(logfile, layout: Chalk::Log.layout)
    ]
  end
end
