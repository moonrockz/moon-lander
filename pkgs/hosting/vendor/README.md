# Vendored core argparse

This folder holds a copy of two `moonbitlang/core` packages. The host needs
`Command::try_parse`, which returns help and version requests to the caller.
The pinned MoonBit release does not have it. When a pinned release has it, the
copy goes away (bead `lander-4us.5.18`).

| Package here | Upstream package |
| --- | --- |
| `moonrockz/moon-lander-hosting/vendor/argparse` | `moonbitlang/core/argparse` |
| `moonrockz/moon-lander-hosting/vendor/internal/edit_distance` | `moonbitlang/core/internal/edit_distance` |

## Source

- Base: `moonbitlang/core` of MoonBit `0.10.17+d971670cd`, the release that
  `.config/mise/config.toml` pins.
- Patch: moonbitlang/core#4487 (issue moonbitlang/core#4486), unchanged. It adds
  `ParseOutcome` and `Command::try_parse`, and `parse` calls `try_parse`.
- Local change: one line. `argparse/moon.pkg` imports `edit_distance` from this
  folder, because a package outside core cannot import a core `internal` package.
- `pkg.generated.mbti` files: `moon info` writes them.
- License: Apache-2.0, as the upstream files say. `LICENSE` and `NOTICE` are the
  upstream files.

## Rules

- Do not edit these files. They stay byte-for-byte equal to the base with the
  patch, except for the one line above. To check, copy the base into an empty
  folder, apply the diff of moonbitlang/core#4487 with `git apply`, and compare.
- The Moon-Lander rules for domain types and for public APIs do not apply here.
  Review only the difference from upstream.
- Do not import these packages directly. The host imports
  `vendor/argparse` under the alias that it used for `moonbitlang/core/argparse`.
  Applications use the type re-exports of `@hosting_argparse`, such as
  `@hosting_argparse.Command`.

## Return to upstream

When a pinned MoonBit release has `Command::try_parse`:

1. Change the MoonBit pin in `.config/mise/config.toml`.
2. In each `moon.pkg` that imports `moonrockz/moon-lander-hosting/vendor/argparse`,
   import `moonbitlang/core/argparse` with the same alias.
3. Delete this folder.
4. Run `mise run lint`, `mise run check`, `mise run check:embedded` and
   `mise run check:console`.

Application code does not change, because the `@hosting_argparse` re-exports
then name the core types.
