# frozen_string_literal: true

require_relative 'lib/feedmob/cli/version'

Gem::Specification.new do |spec|
  spec.name = 'feedmob-cli'
  spec.version = FeedMob::CLI::VERSION
  spec.authors = ['FeedMob']
  spec.email = ['engineering@feedmob.com']

  spec.summary = 'Command-line interface for FeedMob services'
  spec.description = 'A composable CLI for FeedMob Pixel and Time Off APIs.'
  spec.homepage = 'https://github.com/feed-mob/feedmob-cli'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) do
    Dir['README.md', 'LICENSE*', 'exe/*', 'lib/**/*.rb']
  end
  spec.bindir = 'exe'
  spec.executables = ['fm']
  spec.require_paths = ['lib']

  spec.add_dependency 'dry-cli', '~> 1.4'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
