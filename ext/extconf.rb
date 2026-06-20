#!/usr/bin/env ruby
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

return if RUBY_PLATFORM =~ /java/

require "mkmf"

gem_name = File.basename(__dir__)
extension_name = "Ruby_Coverage"

append_cflags(["-Wall", "-Wno-unknown-pragmas", "-std=c99"])

if ENV.key?("RUBY_DEBUG")
	$stderr.puts "Enabling debug mode..."
	
	append_cflags(["-DRUBY_DEBUG", "-O0"])
end

$srcs = ["ruby/coverage/coverage.c", "ruby/coverage/tracer.c"]
$VPATH << "$(srcdir)/ruby/coverage"

if ENV.key?("RUBY_SANITIZE")
	$stderr.puts "Enabling sanitizers..."
	
	append_cflags(["-fsanitize=address", "-fsanitize=undefined", "-fno-omit-frame-pointer"])
	$LDFLAGS << " -fsanitize=address -fsanitize=undefined"
end

have_func("rb_tracearg_instruction_sequence((rb_trace_arg_t *)0)", "ruby/debug.h")

create_header

# Generate the makefile to compile the native binary into `ext/`:
create_makefile(extension_name)
