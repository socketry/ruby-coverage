# Getting Started

This guide explains how to use `ruby-coverage` to collect coverage for code that may be evaluated multiple times under the same path.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add ruby-coverage
~~~

## Core Concepts

`ruby-coverage` has two layers:

- `{ruby Ruby::Coverage}` provides a module-level API similar to Ruby's built-in `Coverage` module.
- `{ruby Ruby::Coverage::Tracer}` is the low-level primitive that decides which counter array should be used for each path.

In both cases, the key design choice is that counters are associated with a file path rather than a specific compiled `ISeq`.

## Basic Usage

If you want a familiar API that behaves like the built-in coverage module, start here:

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

`Ruby::Coverage.result` returns a hash keyed by path. Each value is a hash with a `:lines` array where executable lines contain hit counts, executable-but-unexecuted lines contain `0`, and non-executable lines contain `nil`.

This is the simplest way to get path-based accumulation across repeated evaluation of the same file.

Use `Ruby::Coverage.peek_result` to read counts without stopping coverage:

~~~ ruby
Ruby::Coverage.start

path = "/tmp/example.rb"
Module.new.module_eval("x = 1", path)

result = Ruby::Coverage.peek_result
pp result[path]
# => {:lines=>[nil, 1]}

Ruby::Coverage.result
~~~

Use `Ruby::Coverage.result(stop: false, clear: true)` to clear accumulated counts while keeping coverage active:

~~~ ruby
Ruby::Coverage.start

path = "/tmp/example.rb"
Module.new.module_eval("x = 1", path)

Ruby::Coverage.result(stop: false, clear: true)

pp Ruby::Coverage.peek_result[path]
# => nil

Ruby::Coverage.result
~~~

## Using a Custom Tracer

If you need more control over how counters are allocated or cached, use `{ruby Ruby::Coverage::Tracer}` directly.

This is useful when you need:

- **Custom storage policy**: Reuse one array per path, or deliberately isolate different paths.
- **Selective tracking**: Return `nil` from the callback to skip files you do not care about.
- **Integration with other tooling**: Control exactly when and how coverage data is initialized.

~~~ ruby
require "ruby/coverage"

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

- Use `{ruby Ruby::Coverage}` if you only need path-based accumulation and a familiar API.
- Use `{ruby Ruby::Coverage::Tracer}` if you need custom filtering or storage behavior.
- Reuse the same array for the same path if you want repeated evaluation to accumulate instead of reset.

### Common Pitfalls

- Do not expect stdlib `Coverage` semantics from this library. It intentionally changes the ownership model from `ISeq` to path.
- If you evaluate code under different paths, you will get separate counters even if the source text is identical.
- If you start coverage after code has already been defined, only code executed after startup will be tracked.
