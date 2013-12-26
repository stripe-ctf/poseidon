# Poseidon

A simple utility to allow boot-once, run as many times as you want,
for Ruby applications.

## Usage

```ruby
require 'poseidon'
poseidon = Poseidon.new

poseidon.run do
  puts "This code is run in the context of the client"
  puts "Arguments: #{ARGV.inspect}"
end
```

## How it works

The Poseidon server loads the code for your project and then listens
on a UNIX socket for connections. The client connects and sends the
following:

- Command-line arguments
- Standard input, standard output, standard error

The server then forks, reopens its input/output/error, and the
subprocess executes. Once the subprocess exits, the master responds to
the client with the exitstatus, at which point the client quits.

## Prior art

Zeus is a much more featureful implementation of the same concept:
https://github.com/burke/zeus.

However, Poseidon's simplicity makes it suitable for running in
production. I recommend using it in environments where you need to
boot many copies of a Ruby script. My main use-case is for
non-interactive login shells (think git-shell).

## Limitations

Poseidon does not currently change the forked process's controlling
terminal, meaning you shouldn't use it for things like interactive
shells.
