# Frozen async inputs

These archives are immutable Apache-2.0 inputs to the optional
`moonrockz/moon-lander-moonx` launcher runtime. They are test/build inputs and are
not published in that module. Each contains the upstream license and copyright
notices; generation preserves them.

| Input | SHA-256 | Purpose |
| --- | --- | --- |
| [async 0.22.5 registry archive](https://download.mooncakes.io/user/moonbitlang/async/0.22.5.zip) | `142776b3fac385b8ee97e62fb3213b02a80595ae1a4a80ede6419f452eab01c2` | Production source and upstream tests |
| [async source at 11749dec32e2b4de8cc8a6101e18110019c29893](https://codeload.github.com/moonbitlang/async/tar.gz/11749dec32e2b4de8cc8a6101e18110019c29893) | `50dbf06cf3ae54b2b7cd320fdc3f88ff7f0f9c04cdff347a08861455f21b4c17` | Original test programs and filesystem fixtures omitted from the registry archive |

The second input is the commit referenced by upstream tag `v0.22.5`.
`scripts/moonx-runtime.mbtx` verifies both digests before using either input.
Run `mise run moonx-runtime:generate` after an intentional generator change and
`mise run check:moonx-runtime` to independently reconstruct and compare the
published runtime. Changing a digest requires a source and license review.

The test harness declares its entry, path and readiness adaptations in
`scripts/moonx-runtime.mbtx` and `pkgs/moonx/RUNTIME.md`. Original inputs stay
unchanged. Signal cases wait for the actual fixture handler stage rather than a
fixed startup sleep, retaining their stop/finalizer assertions. The basic wait
case checks pending/completed states around an explicit child release. Retained
native and Wasm suites run sequentially because original timestamp fixtures use
shared `/tmp` names.
