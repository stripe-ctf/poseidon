#!/usr/bin/env ruby

# This is mostly a proof-of-concept: you should use the C
# implementation.

require 'socket'

UNIXSocket.open(ENV['POSEIDON_SOCK'] || '/tmp/poseidon.sock') do |conn|
  args = [$0] + ARGV
  conn.write([args.length].pack('I'))
  args.each do |arg|
    conn.write(arg)
    conn.write("\0")
  end

  conn.send_io(IO.new(0))
  conn.send_io(IO.new(1))
  conn.send_io(IO.new(2))

  exitstatus_packed = conn.read
  exitstatus = exitstatus_packed.unpack('I*').first
  conn.close

  exit(exitstatus)
end
