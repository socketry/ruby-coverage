# Ruby::Coverage

A native reimplementation of Ruby's built-in `Coverage` module, backed by `rb_add_event_hook(RUBY_EVENT_LINE)` rather than ISeq counters.

[![Development Status](https://github.com/socketry/ruby-coverage/workflows/Test/badge.svg)](https://github.com/socketry/ruby-coverage/actions?workflow=Test)

## Motivation

Ruby's built-in `Coverage` module ties its counter store to the ISeq. When a file is re-evaluated under the same path — for example when a test framework loads a file into a fresh anonymous module via `module_eval` — Ruby allocates a fresh counter array and discards the previous one. Any coverage accumulated before the re-eval is lost.

`Ruby::Coverage` owns its own counter store. Re-evaluating a file under the same path simply continues incrementing the same counters. The `covered` gem can optionally use `Ruby::Coverage` in place of `::Coverage` to get correct results in test suites that load files multiple times.

## Usage

Please see the [project documentation](https://socketry.github.io/ruby-coverage/) for more details.

  - [Getting Started](https://socketry.github.io/ruby-coverage/guides/getting-started/index) - This guide explains how to use `ruby-coverage` to collect coverage for code that may be evaluated multiple times under the same path.

### Drop-in module API

``` ruby
require "ruby/coverage"

Ruby::Coverage.start

# ... run code ...

result = Ruby::Coverage.result
# => { "/path/to/file.rb" => { lines: [nil, 3, 1, nil, 0, ...] }, ... }
```

### Low-level `Tracer`

`Ruby::Coverage::Tracer` is the primitive that the module API is built on. It accepts a block that is called once each time execution enters a new file. The block receives the absolute path and must return a Ruby `Array` to use as the line-count store for that file, or `nil` to skip tracking it.

The block controls the caching strategy: returning the same `Array` for the same path accumulates counts across re-evals; returning a fresh `Array` each time gives per-ISeq isolation.

``` ruby
files = {}

tracer = Ruby::Coverage::Tracer.new do |path|
	# Accumulate across re-evals of the same path:
	files[path] ||= []
end

tracer.start
# ... run tests ...
tracer.stop

# files is now populated with line-count arrays keyed by path.
```

## Integration with `covered`

`covered` multiplexes between `Ruby::Coverage` and `::Coverage` internally. Add `ruby-coverage` to your `Gemfile` and `covered` will prefer it automatically.

``` ruby
# gems.rb / Gemfile
gem "ruby-coverage"
gem "covered"
```

## Releases

There are no documented releases.

## See Also

  - [covered](https://github.com/socketry/covered) — the coverage reporting gem that uses this library.
