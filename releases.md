# Releases

## v0.1.2

  - Fix native extension builds on Windows when `rb_tracearg_instruction_sequence` is not declared by Ruby's public headers, and avoid an unused variable compiler warning.

## v0.1.1

  - Fix an unused variable compiler warning in the native extension.

## v0.1.0

  - Improve line-count performance by resizing coverage count arrays in one step.
  - Improve the line-count hot path by updating the internal count array directly while keeping counts as saturated Fixnums.
  - Support accumulating coverage counts independently of Ruby's standard `Coverage` module.
  - Use raw trace arguments for line coverage where available.
  - Add benchmark coverage for tracer load and hot-loop overhead, including comparisons with Ruby's standard `Coverage` module.
  - Improve test coverage around count preparation and subprocess coverage collection.

## v0.0.1

  - Initial release.
