require 'poseidon/version'
require 'chalk-log'
require 'set'

class Poseidon
  include Chalk::Log

  attr_reader :socket_path

  def initialize(socket_path=nil, &blk)
    @socket_path = socket_path || ENV['POSEIDON_SOCK'] || '/tmp/poseidon.sock'
    @blk = blk

    @master_process = $$
    @children = {}
    @loopbreak_reader, @loopbreak_writer = IO.pipe

    Signal.trap('CHLD') {break_loop}
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

  def run
    $0 = 'Poseidon: master'

    listen
    return if is_master?
    @blk.call
  end

  private

  def finalize(conn, pid, exitstatus, termsig)
    log.info('Child died', pid: pid, exitstatus: exitstatus, termsig: termsig)

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
    log.info('Listening for spawn requests', socket_path: socket_path)

    at_exit do
      File.unlink(socket_path) if is_master?
    end

    UNIXServer.open(socket_path) do |server|
      while true
        conn = accept_loop(server)
        if pid = fork
          @children[pid] = conn
          log.info('Spawned child', pid: pid)
        else
          read_argv(conn)
          read_fds(conn)
          set_env
          conn.close
          return
        end
      end
    end
  end

  def read_fds(conn)
    stdin = conn.recv_io
    stdout = conn.recv_io
    stderr = conn.recv_io

    $stdin.reopen(stdin)
    $stdout.reopen(stdout)
    $stderr.reopen(stderr)

    stdin.close
    stdout.close
    stderr.close
  end

  def read_argv(conn)
    argc_packed = conn.read(4)
    argc = argc_packed.unpack('I').first

    argv = argc.times.map do
      conn.readline("\0").chomp("\0")
    end

    program_name = argv.shift
    log.info('About to execute', program_name: program_name, argv: argv)

    $0 = "Poseidon slave: #{program_name || '(unnamed)'}"
    ARGV.clear
    ARGV.concat(argv)
  end

  def set_env
  end

  def is_master?
    @master_process == $$
  end
end
