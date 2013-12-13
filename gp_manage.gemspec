# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gp_manage/version'

Gem::Specification.new do |spec|
  spec.name          = "gp_manage"
  spec.version       = GpManage::VERSION
  spec.authors       = ["Takahiro HIMURA"]
  spec.email         = ["taka@himura.jp"]
  spec.description   = %q{IIJ GP manager}
  spec.summary       = %q{IIJ GP manager}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  spec.add_dependency "thor"
  spec.add_dependency "iij-sakagura"
end
