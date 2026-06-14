# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "rbconfig"

require "ruby/coverage"

describe Ruby::Coverage::Tracer do
	def around
		yield
	ensure
		Ruby::Coverage.result if Ruby::Coverage.running?
	end
	
	it "can be created with a block" do
		tracer = Ruby::Coverage::Tracer.new{|path, iseq| []}
		expect(tracer).not.to be_nil
	end
	
	it "can start and stop" do
		files = {}
		tracer = Ruby::Coverage::Tracer.new{|path, iseq| files[path] ||= []}
		
		tracer.start
		x = 1 + 1
		tracer.stop
		
		expect(files).not.to be(:empty?)
	end
	
	it "calls the callback with path and iseq on script_compiled" do
		paths = []
		iseqs = []
		
		tracer = Ruby::Coverage::Tracer.new do |path, iseq|
			paths << path
			iseqs << iseq
			[]
		end
		
		tracer.start
		Module.new.module_eval("x = 1", "/tmp/ruby_coverage_callback_test.rb")
		tracer.stop
		
		expect(paths).to be(:include?, "/tmp/ruby_coverage_callback_test.rb")
		expect(iseqs.first).to be_a(RubyVM::InstructionSequence)
	end
	
	it "can use a custom callback to track the initial top-level script" do
		script = <<~RUBY
			require_relative "config/environment"
			require "json"
			require_relative "lib/ruby/coverage"

			files = {}

			tracer = Ruby::Coverage::Tracer.new do |path, iseq|
				files[path] ||= begin
					counts = []
					Ruby::Coverage.executable_lines(iseq).each do |line|
						counts[line] = 0
					end
					counts
				end
			end

			tracer.start

			tracked_path = __FILE__
			tracked_line = __LINE__ + 1
			x = 1

			tracer.stop

			puts JSON.generate({
				path: tracked_path,
				tracked_line: tracked_line,
				counts: files[tracked_path],
			})
		RUBY
		
		output = IO.popen([RbConfig.ruby, "-Ilib", "-"], "r+") do |io|
			io.write(script)
			io.close_write
			io.read
		end
		
		result = JSON.parse(output, symbolize_names: true)
		
		expect(result[:path]).to be == "-"
		expect(result[:counts]).not.to be_nil
		expect(result[:counts][result[:tracked_line]]).to be > 0
	end
	
	it "accumulates counts across multiple evals of the same path" do
		files = {}
		tracer = Ruby::Coverage::Tracer.new{|path, iseq| files[path] ||= []}
		
		tracer.start
		
		path = "/tmp/ruby_coverage_tracer_accumulate.rb"
		Module.new.module_eval("x = 1 + 1", path)
		Module.new.module_eval("x = 1 + 1", path)
		
		tracer.stop
		
		counts = files[path]
		expect(counts).not.to be_nil
		expect(counts[1]).to be == 2
	end
	
	it "resizes count arrays for sparse high line numbers" do
		files = {}
		tracer = Ruby::Coverage::Tracer.new{|path, iseq| files[path] ||= []}
		
		tracer.start
		
		path = "/tmp/ruby_coverage_tracer_sparse.rb"
		line = 100
		Module.new.module_eval("x = 1", path, line)
		
		tracer.stop
		
		counts = files[path]
		expect(counts).not.to be_nil
		expect(counts[line]).to be == 1
	end
	
	it "returns nil from the callback to skip tracking a file" do
		files = {}
		tracer = Ruby::Coverage::Tracer.new{|path, iseq| nil}
		
		tracer.start
		Module.new.module_eval("x = 1", "/tmp/ruby_coverage_skipped.rb")
		tracer.stop
		
		expect(files).to be(:empty?)
	end
	
	it "recovers after the callback raises" do
		script = <<~RUBY
			require_relative "config/environment"
			require "json"
			require_relative "lib/ruby/coverage"

			failed = false
			files = {}
			first_path = "/tmp/ruby_coverage_raises_first.rb"
			second_path = "/tmp/ruby_coverage_after_raise.rb"

			tracer = Ruby::Coverage::Tracer.new do |path, iseq|
				if path == first_path && !failed
					failed = true
					raise "boom"
				end

				files[path] ||= []
			end

			tracer.start

			first_error = nil
			begin
				Module.new.module_eval("x = 1", first_path)
			rescue => error
				first_error = error.class.name
			end

			Module.new.module_eval("x = 1", second_path)
			tracer.stop

			puts JSON.generate({
				first_error: first_error,
				tracked_paths: files.keys.sort,
				counts: files[second_path],
			})
		RUBY
		
		output = IO.popen([RbConfig.ruby, "-Ilib", "-"], "r+") do |io|
			io.write(script)
			io.close_write
			io.read
		end
		
		result = JSON.parse(output, symbolize_names: true)
		
		expect(result[:first_error]).to be == "RuntimeError"
		expect(result[:tracked_paths]).to be(:include?, "/tmp/ruby_coverage_after_raise.rb")
		expect(result[:counts][1]).to be == 1
	end
	
	it "supports multiple independent tracers" do
		files_a = {}
		files_b = {}
		
		tracer_a = Ruby::Coverage::Tracer.new{|path, iseq| files_a[path] ||= []}
		tracer_b = Ruby::Coverage::Tracer.new{|path, iseq| files_b[path] ||= []}
		
		tracer_a.start
		tracer_b.start
		
		path = "/tmp/ruby_coverage_multi.rb"
		Module.new.module_eval("x = 1", path)
		
		tracer_a.stop
		tracer_b.stop
		
		expect(files_a[path]).not.to be_nil
		expect(files_b[path]).not.to be_nil
		expect(files_a[path]).not.to be(:equal?, files_b[path])
	end
end
