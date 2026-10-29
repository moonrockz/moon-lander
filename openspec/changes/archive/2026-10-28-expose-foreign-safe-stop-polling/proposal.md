# Expose foreign-safe stop polling

## Why

Issue #128 shows that a JavaScript Promise callback cannot call the task-aware cancellation check. That callback has no current MoonBit task. A synchronous helper still needs the registered signal probes and the retained stop request from the same host lifetime.

## What changes

Add `stop_requested()` to Context, Lifetime and StopToken. Each method reads the existing registered probes and retained request. It does not query current task cancellation. Keep `cancelled()` and `check_cancelled()` unchanged. Document callback use and qualify real JS callbacks, native and embedded callers, and public registry consumers in the next patch.

## Out of scope

No second cancellation state, new scheduler, thread-safety guarantee, downstream workaround or change to signal and exit-code precedence.
