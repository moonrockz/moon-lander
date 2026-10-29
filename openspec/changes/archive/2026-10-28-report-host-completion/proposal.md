# Report host completion

## Why

Issue #130 shows that a pending signal can stop a run before all service hooks and the command. An application cannot write its result from those hooks. The logging bridge owns console finalization and exposes no outcome callback.

## What changes

Add an optional typed completion callback to the console driver and both logging bridge entry points. Call it once after the returned host outcome, failure reports and console finalization, before process exit. Give the real RunOutcome and selected ExitCode. Protect the callback from cancellation. Keep signal precedence and unconditional session cleanup when the callback raises.

## Out of scope

No application result schema, forced command execution, new service event, embedded event loop or downstream workaround. Factory and signal-installation exceptions that occur before a host outcome retain their existing raise and cleanup contract.
