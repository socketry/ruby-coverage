# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "rbconfig"

require "ruby/coverage"

describe Ruby::Coverage do
	def around
		yield
	ensure
		Ruby::Coverage.result if Ruby::Coverage.running?
	end
	
	it "is not running initially" do
		expect(Ruby::Coverage.running?).to be == false
	end
	
	it "can start and is running afterwards" do
		Ruby::Coverage.start
		expect(Ruby::Coverage.running?).to be == true
	end
	
	it "is not running after result" do
		Ruby::Coverage.start
		Ruby::Coverage.result
		expect(Ruby::Coverage.running?).to be == false
	end
	
	it "returns a hash from result" do
		Ruby::Coverage.start
		result = Ruby::Coverage.result
		expect(result).to be_a(Hash)
	end
	
	it "result has the expected shape" do
		Ruby::Coverage.start
		path = "/tmp/ruby_coverage_shape_test.rb"
		Module.new.module_eval("x = 1", path)
		result = Ruby::Coverage.result
		
		expect(result[path]).to be_a(Hash)
		expect(result[path][:lines]).to be_a(Array)
	end
	
	it "pre-initialises executable lines to 0, non-executable lines remain nil" do
		Ruby::Coverage.start
		
		path = "/tmp/ruby_coverage_init_test.rb"
		source = <<~RUBY
			x = 1
			# comment
			if x > 0
				puts "yes"
			end
		RUBY
		
		Module.new.module_eval(source, path)
		result = Ruby::Coverage.result
		
		lines = result[path][:lines]
		# Line 1: x = 1         — executable, was hit: count > 0
		expect(lines[1]).to be > 0
		# Line 2: # comment     — not executable: nil
		expect(lines[2]).to be_nil
		# Line 3: if x > 0      — executable, was hit: count > 0
		expect(lines[3]).to be > 0
		# Line 5: end           — not executable: nil
		expect(lines[5]).to be_nil
	end
	
	it "accumulates counts across re-evals of the same path" do
		Ruby::Coverage.start
		
		path = "/tmp/ruby_coverage_accumulate_test.rb"
		Module.new.module_eval("x = 1", path)
		Module.new.module_eval("x = 1", path)
		
		result = Ruby::Coverage.result
		expect(result.dig(path, :lines, 1)).to be == 2
	end
	
	it "shows executable-but-unexecuted lines as 0" do
		Ruby::Coverage.start
		
		path = "/tmp/ruby_coverage_zero_test.rb"
		source = <<~RUBY
			def greet
				puts "hello"
			end
		RUBY
		
		# Define the method but never call it.
		Module.new.module_eval(source, path)
		result = Ruby::Coverage.result
		
		lines = result[path][:lines]
		# Line 1: def greet    — executable (the def itself), was hit
		expect(lines[1]).to be > 0
		# Line 2: puts "hello" — executable but never called: should be 0
		expect(lines[2]).to be == 0
	end
	
	it "supports peek_result without stopping" do
		Ruby::Coverage.start
		Ruby::Coverage.peek_result
		expect(Ruby::Coverage.running?).to be == true
	end
	
	it "peek_result has the expected shape" do
		Ruby::Coverage.start
		path = "/tmp/ruby_coverage_peek_test.rb"
		Module.new.module_eval("x = 1", path)
		
		result = Ruby::Coverage.peek_result
		expect(result[path]).to be_a(Hash)
		expect(result[path][:lines]).to be_a(Array)
		expect(result[path][:lines][1]).to be == 1
	end
	
	it "supports result with clear: true to reset without stopping" do
		Ruby::Coverage.start
		
		path = "/tmp/ruby_coverage_clear_test.rb"
		Module.new.module_eval("x = 1", path)
		
		Ruby::Coverage.result(stop: false, clear: true)
		expect(Ruby::Coverage.running?).to be == true
		
		result = Ruby::Coverage.peek_result
		expect(result[path]).to be_nil
	end
	
	it "is idempotent when start is called multiple times" do
		Ruby::Coverage.start
		Ruby::Coverage.start
		expect(Ruby::Coverage.running?).to be == true
	end
	
	it "tracks the initial top-level script via the module API" do
		script = <<~RUBY
			require_relative "config/environment"
			require "json"
			require_relative "lib/ruby/coverage"

			Ruby::Coverage.start

			tracked_path = __FILE__
			tracked_line = __LINE__ + 1
			x = 1

			result = Ruby::Coverage.result

			puts JSON.generate({
				path: tracked_path,
				tracked_line: tracked_line,
				counts: result.dig(tracked_path, :lines),
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
	
	with "executable_lines" do
		it "returns executable line numbers from an iseq" do
			source = <<~RUBY
				x = 1
				# comment
				if x > 0
					puts "yes"
				else
					puts "no"
				end
				y = 2
			RUBY
			
			iseq = RubyVM::InstructionSequence.compile(source, "test.rb")
			lines = Ruby::Coverage.executable_lines(iseq)
			
			expect(lines).to be == [1, 3, 4, 6, 8]
		end
		
		it "includes lines from child iseqs (methods, blocks)" do
			source = <<~RUBY
				def greet(name)
					puts name
				end
			RUBY
			
			iseq = RubyVM::InstructionSequence.compile(source, "test.rb")
			lines = Ruby::Coverage.executable_lines(iseq)
			
			# Line 1 (def) is in the parent; line 2 (puts) is in the child iseq.
			expect(lines).to be(:include?, 1)
			expect(lines).to be(:include?, 2)
		end
	end
	
	with "prepare_counts" do
		it "initialises executable lines once per path" do
			source = <<~RUBY
				x = 1
				# comment
				if x
					x += 1
				end
			RUBY
			
			iseq = RubyVM::InstructionSequence.compile(source, "test.rb")
			path = "/tmp/ruby_coverage_prepare_counts.rb"
			
			counts = Ruby::Coverage.send(:prepare_counts, path, iseq)
			counts[1] = 10
			
			expect(counts[1]).to be == 10
			expect(counts[2]).to be_nil
			expect(counts[3]).to be == 0
			expect(counts[4]).to be == 0
			expect(Ruby::Coverage.send(:prepare_counts, path, iseq)).to be(:equal?, counts)
		ensure
			Ruby::Coverage.result if Ruby::Coverage.running?
			Ruby::Coverage.instance_variable_set(:@files, {})
		end
	end
end
