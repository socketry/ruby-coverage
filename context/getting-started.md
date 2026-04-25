# Getting Started

This guide explains how to use `ruby-coverage` to collect coverage for code that may be evaluated multiple times under the same path.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add ruby-coverage
~~~

If you are using `covered`, add that too:

~~~ bash
$ bundle add covered
~~~

## Motivation

Ruby's built-in `Coverage` module stores counters on the compiled instruction sequence (`ISeq`). That works well for ordinary files loaded once, but it breaks down when the same logical file is compiled more than once under the same path.

Use `ruby-coverage` when you need:

- **Stable path-based accumulation**: Re-evaluating the same path should continue incrementing the same counters.
- **Coverage for dynamic loading patterns**: Test frameworks and loaders may use `eval` or `module_eval` with a synthetic filename.
- **A coverage model that matches reporting tools**: If your reporting is path-oriented, resetting counters on every recompile produces misleading results.

Without this library, a recompiled file can replace the previous coverage state because stdlib `Coverage` treats each compile as a distinct `ISeq`. `ruby-coverage` instead owns the counter store and keys it by path.

## Core Concepts

`ruby-coverage` has two layers:

- `{Ruby::Coverage}` provides a module-level API similar to Ruby's built-in `Coverage` module.
- `{Ruby::Coverage::Tracer}` is the low-level primitive that decides which counter array should be used for each path.

In both cases, the key design choice is that counters are associated with a file path rather than a specific compiled `ISeq`.

## Basic Usage

If you want a drop-in API that behaves like the built-in coverage module, start here:

~~~ ruby
require "ruby/coverage"

Ruby::Coverage.start

path = "/tmp/example.rb"
Module.new.module_eval("x = 1", path)
Module.new.module_eval("x = 1", path)

result = Ruby::Coverage.result
pp result[path]
# => {:lines=>[nil, 2]}
~~~

This is the simplest way to get path-based accumulation across repeated evaluation of the same file.

## Using a Custom Tracer

If you need more control over how counters are allocated or cached, use `{Ruby::Coverage::Tracer}` directly.

This is useful when you need:

- **Custom storage policy**: Reuse one array per path, or deliberately isolate different paths.
- **Selective tracking**: Return `nil` from the callback to skip files you do not care about.
- **Integration with other tooling**: Control exactly when and how coverage data is initialized.

~~~ ruby
require_relative "config/environment"
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

path = "/tmp/ruby_coverage_test.rb"
eval("x = 1\n", binding, path, 1)
eval("x = 1\n", binding, path, 1)

tracer.stop

pp files[path]
# => [nil, 2]
~~~

The callback receives the file path and the active `RubyVM::InstructionSequence`. It must return an array to use as the line counter store for that path, or `nil` to skip tracking.

### Best Practices

- Use `{Ruby::Coverage}` if you only need path-based accumulation and a familiar API.
- Use `{Ruby::Coverage::Tracer}` if you need custom filtering or storage behavior.
- Reuse the same array for the same path if you want repeated evaluation to accumulate instead of reset.

### Common Pitfalls

- Do not expect stdlib `Coverage` semantics from this library. It intentionally changes the ownership model from `ISeq` to path.
- If you evaluate code under different paths, you will get separate counters even if the source text is identical.
- If you start coverage after code has already been defined, only code executed after startup will be tracked.

## Integration with `covered`

The `covered` gem can use `ruby-coverage` automatically when it is available.

~~~ ruby
# gems.rb / Gemfile
gem "ruby-coverage"
gem "covered"
~~~

This is a good fit when your test environment re-evaluates files and you want the final report to reflect cumulative path-based execution rather than per-compile counters.