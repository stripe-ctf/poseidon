require 'poseidon'
poseidon = Poseidon.new

poseidon.run do
  puts "This code is run in the context of the client"
  puts "Arguments: #{ARGV.inspect}"
end
