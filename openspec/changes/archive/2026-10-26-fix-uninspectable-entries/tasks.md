## 1. Pass over entries that the host cannot inspect

Bead: lander-4us.45

- [x] 1.1 Add `EntryKind::Inaccessible` and `FileTree::file_request`; make `FileTree::is_file` and the member search ask for an inaccessible candidate before they count candidates; test the pure rules on all four targets.
- [x] 1.2 Record uninspectable entries as `Inaccessible` and omit vanished entries in the native and js host adapters; add private inspection seams and injected tests for a Windows sharing violation, a vanished entry, an inaccessible candidate, and an error that is not a system error; keep the real link-loop and permission tests.
- [x] 1.3 Remove the boundary workaround from the hosting-config acceptance tests and add an unbounded Windows acceptance run; archive this change and validate all specifications strictly.
