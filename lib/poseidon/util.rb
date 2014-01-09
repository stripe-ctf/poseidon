module Poseidon::Util
  # Try to escape from environment set up by bundler. This code isn't
  # pretty, but it works. You can call it from within Poseidon if you
  # want the subprocesses you spawn to be free of bundler's influence.
  def self.unbundle
    ENV.delete('RUBYOPT')
    ENV['PATH'] = ENV['PATH'].
      split(':').
      reject { |p| (ENV['RBENV_ROOT'] && p =~ %r{^#{ENV['RBENV_ROOT']}}) || p =~ %r{/vendor/bundle/} }.
      join(':')
    ENV.delete_if do |key, _|
      key.start_with?('BUNDLE_') || key.start_with?('GEM_') || key.start_with?('RBENV_')
    end
  end
end
