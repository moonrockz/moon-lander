# Preserve DIB source cells

## Why

The published DIB codec drops empty cells and trims empty boundary lines. This
blocks the source-cell round trip required by Morphir adoption and issue #109.

## What Changes

- Add an explicit `SourceMode::Lossless` option to cell construction, parsing and
  writing. Keep `Normalized` as the compatible default.
- Retain empty cells, empty boundary lines, cell order and canonical kernel names
  in a lossless public-API round trip, using the same custom registry on reread.
- Keep line-ending normalization, document metadata and typed refusal of source
  that cannot be represented without changing cell boundaries.

## Capabilities

### New Capabilities

- `dib-source-roundtrip`: compatible normalized DIB behavior and an opt-in lossless
  source-cell representation through the public notebook API.

### Modified Capabilities

None.

## Impact

The DIB model, codec, public interface and runnable examples change. No dependency,
execution output, persisted application format or existing default changes.
The new option is required for finos/morphir-moonbit#268 and resolves
moonrockz/moon-lander#109.

## Out of scope

Execution results, byte-exact line endings, new directives, automatic registry
injection, unrelated notebook domain-type changes and diagnostic JSON issue #112.
