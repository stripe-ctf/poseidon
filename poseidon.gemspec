# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'poseidon/version'

Gem::Specification.new do |spec|
  spec.name          = 'poseidon'
  spec.version       = Poseidon::VERSION
  spec.authors       = ['Greg Brockman']
  spec.email         = ['gdb@gregbrockman.com']
  spec.description   = %q{Boot once, run many times, for Ruby apps}
  spec.summary       = %q{Load the code in a master process, and then fork and run your client's code}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
  spec.extensions = ['ext/extconf.rb']
  spec.add_dependency 'chalk-log'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'minitest', '< 5.0'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency 'mocha'
  spec.add_development_dependency 'chalk-rake'

  spec.add_development_dependency 'bundler', '~> 1.3'
end
