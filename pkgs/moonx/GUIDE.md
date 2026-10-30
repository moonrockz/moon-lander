# Launch a process from Moonx

Add `moonrockz/moon-lander-moonx` at the workspace's published shared version to
your module. Import its pure plan package and `driver` from a Wasm or native
executable:

```moonbit
// moon.pkg
import {
  "moonrockz/moon-lander-moonx" @moonx,
  "moonrockz/moon-lander-moonx/driver",
  "moonbitlang/core/env",
}
supported_targets = "wasm+native"
pkgtype(kind: "executable")
```

```moonbit
fn main raise {
  let args = @env.args()
  let command = @moonx.Command::new(
    @moonx.Executable::node(),
    @moonx.Arguments::parse(args[1:].to_owned()),
  )
  @driver.run(Process(command))
}
```

Use synchronous `fn main`, rather than `async fn main`. The driver owns one
isolated runtime. Stock `0.10.16+b1a0e846e` and `0.10.17+d971670cd` Moonx run a
prebuilt Wasm executable, while the Node child runs the application. The pure
plan package builds on Wasm, Wasm GC, JS and native; the process driver and owned
runtime support Wasm and native. Node must be available through PATH, or be
selected with `Executable::parse`.

Executable text must be nonempty and NUL-free. Arguments reject only NUL and
preserve empty elements, option-looking strings, delimiters, spaces, newlines
and Unicode. No shell splits or interprets them. Binary stdin, stdout and stderr
are inherited directly and remain separate. The child retains the caller's cwd.
An idle stdin writer can remain open through child termination.

On POSIX process hosts, the driver forwards the first observed SIGINT, SIGTERM
or SIGHUP to the child. The positive `ShutdownGrace` defaults to five seconds;
a child still running at its deadline receives a hard termination request.
The driver waits for reaping before cleanup and completion. The first forwarding
identity remains fixed across repeated signals; the upstream runtime's existing
exit selection can change when a later signal arrives.

Windows process statuses retain all 32 bits. Console control events have Windows
semantics: stock process hosts support targeted Ctrl-Break and hard termination;
SIGTERM is not a Windows console event. Ctrl-C delivery requires separate console
qualification and must not be inferred from a Ctrl-Break test. See the release's
host qualification evidence for the tested stock tools and console setup.

# Embed a Node payload

Describe the complete runtime closure as immutable relative files, including its
package manifest, entry wrapper, workers and runtime files. The application owns
assembly, hashing and generation of these bytes. The framework owns their
private materialization and process lifetime:

```moonbit
fn main raise {
  let entry = @moonx.RelativeFilePath::parse("entry.js")
  let payload = @moonx.Payload::new([
    @moonx.PayloadFile::new(
      @moonx.RelativeFilePath::parse("package.json"),
      b"{\"type\":\"module\"}",
    ),
    @moonx.PayloadFile::new(entry, b"console.log(process.cwd());"),
  ], entry)
  let node = @moonx.NodeLaunch::new(payload, @moonx.Arguments::empty())
  @driver.run(Node(node))
}
```

The driver creates a new exclusive directory with POSIX mode 0700 and creates
files exclusively with mode 0600. It passes the absolute entry path to Node
without changing cwd or consuming stdin. Payload bytes never travel through
argv or eval. Windows uses its host access-control policy; POSIX permission bits
do not imply a Windows ACL guarantee. This facility is process lifetime ownership,
not a sandbox against code with the same user's filesystem permissions.

Asset names are portable ASCII relative paths. Construction rejects traversal,
empty/dot segments, backslashes, controls, Windows reserved characters and device
names, trailing dots/spaces, and `~` short-name aliases. The collection rejects
case-insensitive duplicate identities, inconsistent directory case, file/directory
prefix collisions and an entry whose exact retained spelling is absent. This
restriction applies only to payload-owned names: argv, cwd, host temporary paths
and file bytes preserve Unicode. Filesystem resource or permission errors remain
typed startup failures before a child starts.

After reaping, protected cleanup removes the owned directory, including partial
materialization, without following a root symlink or child symlinks outside it.
It tolerates an already removed root. The driver finalizes once and reports the
outcome after cleanup, including startup failure and cancellation during writes.

# Report completion in the application

Supply `finalize=() => ...` for synchronous application cleanup and
`completed=outcome => ...` for result reporting. These callbacks receive no
compatibility-runtime or canonical-async values. The outcome distinguishes
`NotStarted(Failed(...))`, `NotStarted(Cancelled(...))` and `Started(...)`.
Startup failures distinguish materialization, missing Node and other process
startup errors. A started child reports its actual status and, on cancellation,
the observed cause and whether hard termination was requested. The latter is
an action observation, not a guess about cause of death.

`outcome.selected_status()` is the parent selection after payload cleanup and
finalization. Its unsigned `bits()` preserves Windows values such as
`0xc000013a`; `to_int()` preserves those bits at the exit boundary. A finalization
failure changes selected success into failure and preserves a previous failure
or signal selection. Completion sees the selection before its own invocation;
its failure can also change success into failure. A later signal can still alter
the runtime's exit selection.

The application owns JSON, result envelopes and error formatting. A not-started
outcome lets it emit a startup report without inspecting stdout or reproducing
lifetime logic. Once the child has started, its result channel stays opaque;
the framework adds no application document to stdout.

See [RUNTIME.md](RUNTIME.md) for provenance, retained tests, maintenance and the
return path to a released public upstream observer. Existing hosting, actor and
embedded applications continue using canonical async and must not import this
owned runtime into their executable.

## Qualification and public release proof

`mise run check:moonx` and `mise run check:moonx-stock16` build independent
consumers with the two supported stock toolchains. They check real console-host
completion, idle stdin, repeated signals during finalization, ignored-signal
forced reaping, cancellation during materialization, and opaque binary streams.
The candidate registry serves only the public `/launch` Wasm asset and its
checksum to a fresh Moonx home. Its report explicitly says it is local evidence.

After publication, `mise run check:moonx-published` reads the pre-publication
approved digest from `_build/publish/checksums.json`. Both stock consumers use
fresh homes and the default public registry. The source archive must match that
approved digest, the independent parent must resolve the public module without
a workspace override, and stock Moonx must download the public `/launch` asset.
The gate compares the public asset, advertised checksum and actual fresh cached
Wasm before running genuine Node-owned host completion again. Public reports
are retained as `_build/moonx/qualification-published-*.json`. Source checks and
candidate simulations do not count as a successful public release proof.
