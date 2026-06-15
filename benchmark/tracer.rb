# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "../config/environment"

require "coverage"
require "sus/fixtures/benchmark"
require "tmpdir"

require "ruby/coverage"

describe Ruby::Coverage::Tracer do
	include Sus::Fixtures::Benchmark
	
	SAMPLES = 8
	
	def around
		Dir.mktmpdir do |root|
			@path = File.join(root, "workload.rb")
			
			File.write(@path, <<~RUBY)
				i = 0
				total = 0
				while i < 1_000_000
					total += i
					i += 1
				end
				total
			RUBY
			
			yield
		end
	end
	
	attr :path
	
	def stop_standard_coverage
		if ::Coverage.running?
			::Coverage.result(stop: true, clear: true)
		end
	end
	
	measure "load without coverage" do |repeats|
		repeats.exactly(SAMPLES).times do
			load(self.path)
		end
	end
	
	measure "load with stdlib coverage" do |repeats|
		repeats.exactly(SAMPLES).times do
			begin
				::Coverage.start(lines: true)
				load(self.path)
			ensure
				stop_standard_coverage
			end
		end
	end
	
	measure "load with ruby coverage" do |repeats|
		repeats.exactly(SAMPLES).times do
			tracer = Ruby::Coverage::Tracer.new do |_path, iseq|
				counts = []
				
				Ruby::Coverage.executable_lines(iseq).each do |line|
					counts[line] = 0
				end
				
				counts
			end
			
			begin
				tracer.start
				load(self.path)
			ensure
				tracer.stop
			end
		end
	end
end
