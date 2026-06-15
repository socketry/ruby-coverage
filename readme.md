# Ruby::Coverage

A native reimplementation of Ruby's built-in `Coverage` module, backed by `rb_add_event_hook(RUBY_EVENT_LINE)` rather than ISeq counters.

[![Development Status](https://github.com/socketry/ruby-coverage/workflows/Test/badge.svg)](https://github.com/socketry/ruby-coverage/actions?workflow=Test)

## Motivation

Ruby's built-in `Coverage` module ties its counter store to the ISeq. When a file is re-evaluated under the same path — for example when a test framework loads a file into a fresh anonymous module via `module_eval` — Ruby allocates a fresh counter array and discards the previous one. Any coverage accumulated before the re-eval is lost.

`Ruby::Coverage` owns its own counter store. Re-evaluating a file under the same path simply continues incrementing the same counters, which gives path-oriented reporting tools stable results when test suites load files multiple times. In addition, multiple `Ruby::Coverage::Tracer` instances can be active at the same time, so tools can collect independent coverage streams such as per-test coverage without fighting over Ruby's global `Coverage` state.

## Usage

Please see the [project documentation](https://socketry.github.io/ruby-coverage/) for more details.

  - [Getting Started](https://socketry.github.io/ruby-coverage/guides/getting-started/index) - This guide explains how to use `ruby-coverage` to collect coverage for code that may be evaluated multiple times under the same path.

## Releases

Please see the [project releases](https://socketry.github.io/ruby-coverage/releases/index) for all releases.

### v0.1.2

  - Fix native extension builds on Windows when `rb_tracearg_instruction_sequence` is not declared by Ruby's public headers, and avoid an unused variable compiler warning.

### v0.1.1

  - Fix an unused variable compiler warning in the native extension.

### v0.1.0

  - Improve line-count performance by resizing coverage count arrays in one step.
  - Improve the line-count hot path by updating the internal count array directly while keeping counts as saturated Fixnums.
  - Support accumulating coverage counts independently of Ruby's standard `Coverage` module.
  - Use raw trace arguments for line coverage where available.
  - Add benchmark coverage for tracer load and hot-loop overhead, including comparisons with Ruby's standard `Coverage` module.
  - Improve test coverage around count preparation and subprocess coverage collection.

### v0.0.1

  - Initial release.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Running Tests

To run the test suite:

``` shell
bundle exec sus
```

### Making Releases

To make a new release:

``` shell
bundle exec bake gem:release:patch # or minor or major
```

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
