require 'chalk-log'
require 'chalk-tools'
require 'einhorn/worker'
require 'chalk-tools'
require 'set'
require 'tempfile'
require 'fileutils'

require 'poseidon/version'
begin
  require 'poseidon_ext'
rescue LoadError => e
  begin
    require_relative '../ext/poseidon_ext'
  rescue LoadError
    raise e
  end

  $stderr.puts "WARNING: Poseidon is falling back to a manually-specified poseidon_ext path. This should only be needed in development."
end

require 'poseidon/ssh_strategy'
require 'poseidon/util'

class Poseidon
  include Chalk::Log

  attr_reader :socket_path

  def initialize(socket_path=nil, opts={})
    @socket_path = socket_path || ENV['POSEIDON_SOCK'] || '/tmp/poseidon.sock'
    @opts = opts

    @master_process = $$
    @children = {}
    @loopbreak_reader, @loopbreak_writer = IO.pipe

    @strategy = opts[:strategy] || Poseidon::SSHStrategy.new

    munge_socket_path
  end

  def run(&blk)
    chld = Signal.trap('CHLD') {break_loop}
    Chalk::Tools::GracefulExit.setup {break_loop}

    interpretation = listen
    return if is_master?

    # TODO: ideally, we'd always set this to chld, but that actually
    # means IGNORE if chld is nil
    Signal.trap('CHLD', chld || 'DEFAULT')
    Chalk::Tools::GracefulExit.teardown
    blk.call(interpretation)
  end

  private

  # Useful for atomic cutovers
  def munge_socket_path
    if @opts[:symlink]
      @socket_symlink_path = @socket_path

      tempfile = Tempfile.new(File.basename(@socket_path),
        File.dirname(@socket_path))
      @socket_path = tempfile.path
      # Might be easier just to generate my own random filenames
      tempfile.delete
      tempfile.close
    else
      @socket_symlink_path = nil
    end
  end

  def break_loop
    begin
      @loopbreak_writer.write_nonblock('a')
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN
    end
  end

  def reap
    begin
      while true
        pid = Process.wait(-1, Process::WNOHANG)
        return unless pid

        conn = @children.delete(pid)
        exitstatus = $?.exitstatus
        termsig = $?.termsig
        finalize(conn, pid, exitstatus, termsig)
      end
    rescue Errno::ECHILD
    end
  end

  def finalize(conn, pid, exitstatus, termsig)
    log.info('Child exited', pid: pid, exitstatus: exitstatus, termsig: termsig)

    begin
      if termsig
        conn.write([123].pack('I'))
      elsif exitstatus
        conn.write([exitstatus].pack('I'))
      else
        raise "Invalid statuses: exitstatus #{exitstatus.inspect}, termsig: #{termsig.inspect}"
      end
    rescue Errno::EPIPE => e
      log.info('Client has gone away', error: e.message)
    end

    conn.close
  end

  def accept_loop(server)
    while true
      Chalk::Tools::GracefulExit.checkpoint if @children.length == 0
      readers, _, _ = IO.select([server, @loopbreak_reader])
      if readers.include?(@loopbreak_reader)
        @loopbreak_reader.readpartial(4096)
        reap
      end

      if readers.include?(server)
        return server.accept
      end
    end
  end

  def listen
    at_exit do
      File.unlink(socket_path) if is_master?
    end

    UNIXServer.open(socket_path) do |server|
      log.info('Listening for Poseidon requests', socket_path: socket_path)
      post_open

      while true
        conn = accept_loop(server)
        if pid = fork
          @children[pid] = conn
          log.info('Spawned child', pid: pid)
        else
          identity = Poseidon::Ext.get_identity(conn)
          fds = read_fds(conn)
          args = read_args(conn)
          conn.close
          interpretation = @strategy.interpret(identity, fds, args)
          return interpretation
        end
      end
    end
  end

  def read_args(conn)
    argc_packed = conn.read(4)
    argc = argc_packed.unpack('I').first

    args = argc.times.map do
      conn.readline("\0").chomp("\0")
    end

    args
  end

  def read_fds(conn)
    stdin = conn.recv_io
    stdout = conn.recv_io
    stderr = conn.recv_io
    [stdin, stdout, stderr]
  end

  def is_master?
    @master_process == $$
  end

  # TODO: refactor into strategy, perhaps
  def post_open
    chmod_socket
    setup_symlink
    ack_einhorn
  end

  def chmod_socket
    return unless mode = @opts[:socket_permissions]
    File.chmod(mode, socket_path)
  end

  def setup_symlink
    return unless @socket_symlink_path
    log.info('Creating symlink', target: @socket_path, source: @socket_symlink_path)
    Poseidon::Util.atomic_symlink(@socket_path, @socket_symlink_path)
  end

  def ack_einhorn
    Einhorn::Worker.ack
  end
end
