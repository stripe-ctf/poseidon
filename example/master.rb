require 'poseidon'
require 'poseidon'
poseidon = Poseidon.new do
  puts "This code is run in the context of the client"
  puts "Arguments: #{ARGV.inspect}"
  exit 4
end

poseidon.run
