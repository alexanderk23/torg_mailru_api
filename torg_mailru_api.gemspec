# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'torg_mailru_api/version'

Gem::Specification.new do |spec|
  spec.name          = "torg_mailru_api"
  spec.version       = TorgMailruApi::VERSION
  spec.authors       = ["Alexander Kovalenko"]
  spec.email         = ["alexanderk23@gmail.com"]
  spec.description   = %q{Torg.Mail.Ru Content API Wrapper}
  spec.summary       = %q{Torg.Mail.Ru Content API Wrapper}
  spec.homepage      = "https://github.com/alexanderk23/torg_mailru_api"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "redcarpet"

  spec.add_runtime_dependency 'faraday', '~> 0.8.8'
  spec.add_runtime_dependency 'faraday_middleware', '~> 0.9.0'
end
