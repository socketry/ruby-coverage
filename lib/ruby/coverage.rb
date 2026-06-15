# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "coverage/version"

require "Ruby_Coverage"

module Ruby
	# A reimplementation of Ruby's built-in `Coverage` module backed by
	# `rb_add_event_hook(RUBY_EVENT_LINE)` rather than ISeq counters.
	#
	# The key behavioural difference: re-evaluating a file under the same path
	# (e.g. via `module_eval`) accumulates hit counts rather than resetting
	# them, because the counter store is owned here rather than inside the ISeq.
	#
	# The module-level API mirrors `::Coverage` closely enough that `covered`
	# can multiplex between the two, preferring this implementation when
	# available and falling back to `::Coverage` otherwise.
	module Coverage
		@tracer = nil
		@files  = {}
		
		class << self
			# Walk the instruction sequence to find which lines carry a
			# RUBY_EVENT_LINE event — these are the executable lines.
			#
			# Lines without this event (comments, `else`, `end`, blank lines)
			# remain nil in the counts array, matching the nil/0 distinction
			# used by Ruby's built-in Coverage module.
			#
			# Recurses into child ISeqs (methods, blocks, lambdas) via
			# `each_child` so that all executable lines across the entire
			# compilation unit are collected.
			#
			# @parameter iseq [RubyVM::InstructionSequence]
			# @returns [Array(Integer)] Sorted, deduplicated executable line numbers.
			def executable_lines(iseq)
				lines = []
				current_line = nil
				
				iseq.to_a[13].each do |element|
					case element
					when Integer          then current_line = element
					when :RUBY_EVENT_LINE then lines << current_line
					end
				end
				
				iseq.each_child{|child| lines.concat(executable_lines(child))}
				
				lines.sort!
				lines.uniq!
				lines
			end
			
			# Start coverage tracking.
			#
			# The callback receives (path, iseq) for each newly compiled file and
			# must return a Ruby Array to use as the line-count store for that
			# file, or nil to skip it. Executable lines are pre-initialised to 0;
			# non-executable lines remain nil.
			#
			# Safe to call multiple times; subsequent calls are no-ops.
			# Returns self.
			def start
				return self if @tracer
				
				@files  = {}
				@tracer = Tracer.new(&method(:prepare_counts))
				@tracer.start
				
				self
			end
			
			# Whether coverage is currently being tracked.
			#
			# @returns [Boolean]
			def running?
				!@tracer.nil?
			end
			
			# Return the current line-count data without stopping the tracer.
			#
			# The returned hash has the same shape as `::Coverage.peek_result`:
			#   { "/absolute/path.rb" => { lines: [nil, 0, 3, nil, ...] }, ... }
			#
			# @returns [Hash]
			def peek_result
				@files.transform_values{|counts| {lines: counts}}
			end
			
			# Return coverage results, optionally stopping or clearing the tracer.
			#
			# @parameter stop [Boolean] Stop tracking after returning results
			#   (default: true).
			# @parameter clear [Boolean] Clear accumulated data and restart without
			#   stopping (default: false).
			# @returns [Hash] Same shape as {peek_result}.
			def result(stop: true, clear: false)
				result = peek_result
				
				if stop
					@tracer&.stop
					@tracer = nil
					@files  = {}
				elsif clear
					@tracer&.stop
					@files  = {}
					@tracer = Tracer.new(&method(:prepare_counts))
					@tracer.start
				end
				
				result
			end
			
			private
			
			def prepare_counts(path, iseq)
				@files[path] ||= begin
					counts = []
					executable_lines(iseq).each{|line| counts[line] = 0}
					counts
				end
			end
		end
	end
end
