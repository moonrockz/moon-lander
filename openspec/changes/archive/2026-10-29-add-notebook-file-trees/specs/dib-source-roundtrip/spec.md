# Nested notebook kernel registrations

## ADDED Requirements

### Requirement: Nested kernel registration namespaces

The DIB codec SHALL accept nested polyglot_notebook.kernelInfo and legacy
dotnet_interactive.kernelInfo declarations. Existing top-level kernelInfo and
flat namespace forms SHALL remain compatible. Names, aliases and default kernels
SHALL use the existing typed registry rules.

#### Scenario: Self-describing converted source

- **WHEN** a document declares Python and its alias in a nested kernelInfo namespace
- **THEN** reading resolves that alias and rereading its output retains the same cells
