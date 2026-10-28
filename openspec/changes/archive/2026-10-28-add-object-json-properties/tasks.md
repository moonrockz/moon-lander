# Add object JSON properties

## 1. Implement and qualify the approved policy

Bead: lander-fby.1

- [x] 1.1 Add the schema version 2 object formatter and typed policy, retaining the existing formatter signature and array default; test last-wins lookup, complete ordered histories, omission, mixed JSON types, escaping and metadata isolation on all four targets
- [x] 1.2 Add FileSink policy selection and public rolling acceptance on native and JS, including independent JSON decoding, rolls, drains and default-format compatibility
- [x] 1.3 Update runnable formatter/sink docs, generated interfaces and registry consumer evidence; run format, strict OpenSpec validation, focused checks and mise run check before review

## Workflow follow-up

Archive the completed change in its implementation PR. After green reviewed
merge, close and sync the bead and epic. Include the change in the authorized
shared-version publication.
