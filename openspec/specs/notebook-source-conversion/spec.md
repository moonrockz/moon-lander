# Notebook source conversion

## Purpose
Convert source notebooks between DIB and Jupyter while making data loss explicit.

## Requirements

### Requirement: Tree format conversion

The library SHALL offer an open tree-format trait and a conversion operation
through the shared tree model. Both file-tree adapters SHALL implement it.
The operation SHALL use the documented tree projection and perform no I/O.

#### Scenario: File trees across formats

- **WHEN** a DIB tree is converted to Jupyter and back using configured formats
- **THEN** file source, paths, canonical kernels and empty directories are retained

### Requirement: Source notebook conversion

A configured source converter SHALL preserve source-cell order and LF-normalized
source, including empty cells. It SHALL retain kernel identity using per-cell
polyglot_notebook.kernelName metadata and declared kernel registrations. Markdown
and plain text SHALL map to Markdown and raw cells. Existing document metadata
SHALL remain subject to each target's supported metadata types.

#### Scenario: Custom source kernels

- **WHEN** empty MoonBit, Python and Markdown source cells are converted to Jupyter and back with explicit source-only policy
- **THEN** their order, source and kernels are retained

### Requirement: Explicit conversion loss

Conversion results SHALL expose a typed loss list. Jupyter-to-DIB conversion SHALL
report cell IDs, unsupported cell metadata, root or cell extensions, outputs,
execution counts and attachments. Strict policy SHALL refuse a nonempty loss
list; source-only policy SHALL return it with the converted source notebook.
Unknown cell types SHALL be refused rather than assigned invented source.

#### Scenario: Execution state refusal

- **WHEN** Jupyter cells with outputs or attachments are converted under strict policy
- **THEN** a typed conversion error reports the losses

#### Scenario: Explicit source conversion

- **WHEN** the caller selects source-only conversion
- **THEN** the result includes source and a typed report of discarded data
