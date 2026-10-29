# Add notebook file trees

## Why

Consumers need to describe immutable virtual text file trees in DIB and Jupyter
notebooks. Repeated kernel registrations and source-mode arguments add ceremony.
The owner approved a kernel descriptor, a configured DIB codec and a file-tree
format, and requested the format-neutral `metadata.vfs` namespace for Jupyter.

## What Changes

- Add a kernel descriptor trait and an immutable configured DIB codec.
- Add typed relative tree paths, text files and an immutable virtual tree.
- Map DIB first-line file directives and manifest directory declarations to trees.
- Map Jupyter `metadata.vfs` file entries and notebook directory metadata to the
  same tree. Keep cell source free of transport directives.
- Add explicit format conversion for trees and source notebooks, with typed loss reports and strict refusal of unsupported state.
- Preserve ordinary notebook APIs, normalized DIB defaults and package boundaries.
- Add runnable public examples and four-target regression coverage.

## Capabilities

### New Capabilities

- `notebook-file-trees`: immutable text file trees and DIB/Jupyter mappings.
- `notebook-source-conversion`: explicit source conversion and loss reporting.
- `configured-dib-codec`: reusable typed kernel registration and source policy.

### Modified Capabilities

- `dib-source-roundtrip`: accept nested Polyglot and legacy kernel registrations.

## Impact

New packages live within the existing notebooks module. No new dependency or
published module is required. No version change or publication is included.

## Out of Scope

Disk writes, execution, binary files, symlinks, overlay conflict policies and a
configuration-module adapter are outside this change. Tree extraction is a
projection, not a complete notebook conversion preserving outputs or notes.
