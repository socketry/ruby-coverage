# frozen_string_literal: true

require_relative "lib/ruby/coverage/version"

Gem::Specification.new do |spec|
	spec.name = "ruby-coverage"
	spec.version = Ruby::Coverage::VERSION
	
	spec.summary = "A native reimplementation of Ruby's Coverage module with accumulating line counts."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/ruby-coverage"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/ruby-coverage/",
		"source_code_uri" => "https://github.com/socketry/ruby-coverage.git",
	}
	
	spec.files = Dir["{ext,lib}/**/*", "*.md", base: __dir__]
	spec.require_paths = ["lib"]
	
	spec.extensions = ["ext/extconf.rb"]
	
	spec.required_ruby_version = ">= 3.3"
end
