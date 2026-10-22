# Frozen OpenRPC qualification inputs

These unpublished test assets preserve upstream bytes. `SHA256SUMS` records the
SHA-256 of every source asset and license. The verifier reads binary bytes,
rejects malformed or incomplete manifests, and never fetches remote resources.

Run from the workspace root:

```sh
mise exec -- moonx scripts/check-openrpc-assets.mbtx
mise exec -- moon test --deny-warn --target wasm scripts/check-openrpc-assets.mbtx
mise exec -- moonx scripts/check-openrpc-assets.mbtx --verify-failures
```

The last command copies the inputs into a temporary directory. It proves that
corruption, a missing file, and a malformed manifest each cause the verifier
process to exit nonzero with the expected diagnostic. It leaves the frozen
files unchanged. `--assets <directory>` checks another copy with the same required
file inventory. Asset integrity alone does not establish library conformance.

## Provenance

Frozen on 2026-10-21. The asset release, OpenRPC document version, JSON Schema
draft, and this repository's package version are separate identities.

| File | Upstream source and identity |
| --- | --- |
| `openrpc-1.3.2-spec.md` | [OpenRPC 1.3.2 prose](https://github.com/open-rpc/spec/blob/df0df86da41d3a67b35a4b320067748344e035b5/spec.md), commit `df0df86da41d3a67b35a4b320067748344e035b5`, fetched from its raw GitHub URL |
| `open-rpc-meta-schema.json` | [Official meta-schema release 1.14.9](https://github.com/open-rpc/meta-schema/releases/download/1.14.9/open-rpc-meta-schema.json), recovered from the Smithy baseline below; accepts document version 1.3.2 |
| `json-schema-meta.json` | Official companion endpoint `https://meta.json-schema.tools`, frozen by Smithy on 2026-10-21 and recovered unchanged from the baseline below |
| `json-schema-meta-alias.json` | Smithy's local alias resource, recovered unchanged from the baseline below |
| `openrpc-1.4-schema.json` | [Official 1.4 schema](https://github.com/open-rpc/spec/blob/876aa30e341f7669f5ba261e89520a5fc3057038/spec/1.4/schema.json), commit `876aa30e341f7669f5ba261e89520a5fc3057038` |
| `openrpc-1.4-spec-template.md` | [Official 1.4 prose template](https://github.com/open-rpc/spec/blob/876aa30e341f7669f5ba261e89520a5fc3057038/spec/1.4/spec-template.md), same commit |
| `draft-07-schema.json` | [Official draft-07 metaschema](https://json-schema.org/draft-07/schema), retrieved directly on 2026-10-21; SHA-256 `692e1d165e47afcb5f11b2ce1c639635ffa834035d6ecb6bcf3087481dae8404` |
| `DerivedCoreProperties-10.0.0.txt` | [Official Unicode 10.0.0 data](https://www.unicode.org/Public/10.0.0/ucd/DerivedCoreProperties.txt), unchanged bytes, SHA-256 `e6ca152259189ec4bc2297e93c6c88f86e162cc52814198263497f3c9b46cbe9` |
| `LICENSE-unicode.txt` | [Unicode License v3](https://www.unicode.org/license.txt), frozen on 2026-10-22, SHA-256 `e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96` |

The Smithy baseline is [moonrockz/smithy at
`c36698b3bd08be62d5d80e93b727ce736388adf6`](https://github.com/moonrockz/smithy/tree/c36698b3bd08be62d5d80e93b727ce736388adf6/tests/tck/openrpc).
The documented evidence checkout was absent in this environment. Only that
commit was fetched into a temporary bare repository. The three files were
extracted with `git show <commit>:tests/tck/openrpc/<filename>`. No Smithy
checkout, generated output, or build was used. The schema hashes match the
previously recorded baseline identities `e5f534fb...d0f82` and
`c6054943...14738`; the manifest contains their complete values.

## Offline schema resources

Register `json-schema-meta.json` under its unchanged `$id`,
`https://meta.json-schema.tools/`. Register `json-schema-meta-alias.json` under
`https://meta.json-schema.tools`; its `$ref` targets the slash-terminated ID.
This supports the reference spelling in both OpenRPC schemas without editing
upstream documents.

`draft-07-schema.json` has the canonical ID
`http://json-schema.org/draft-07/schema#`. An independent validator can associate
the HTTP and HTTPS draft-07 URI spellings with these same frozen bytes. Such
resource registration is a validator input, not a rewrite of the schemas.
Qualification must use explicit local resources and disable remote retrieval.

## Licenses

The assets keep their upstream licenses; the repository's license does not
replace them.

- `LICENSE-openrpc.md` is the unmodified Apache-2.0 license from [the 1.3.2 prose
  commit](https://github.com/open-rpc/spec/blob/df0df86da41d3a67b35a4b320067748344e035b5/LICENSE.md).
  The 1.4 prose/schema commit and meta-schema tag `1.14.9` have identical license
  bytes. It covers their respective OpenRPC assets.
- `LICENSE-json-schema-tools.md` is the unmodified Apache-2.0 license from
  [json-schema-tools/meta-schema commit
  `3f340ae906f45278f62d16fc68741cd0c2d33eaf`](https://github.com/json-schema-tools/meta-schema/blob/3f340ae906f45278f62d16fc68741cd0c2d33eaf/LICENSE.md),
  the companion schema's upstream project. Its bytes match the OpenRPC license,
  but it is retained separately to record provenance.
- The draft-07 source repository [declares AFL or BSD licensing](https://github.com/json-schema-org/json-schema-spec/blob/1afc34b65ead445ff363cfc870a28de0ca56e20f/README.md#license).
  `LICENSE-draft-07.txt` preserves the complete upstream BSD-3-Clause and AFL-3.0
  text from [commit
  `51326f80900357fe3069beb4f5f575db24c1b9a7`](https://github.com/json-schema-org/json-schema-spec/blob/51326f80900357fe3069beb4f5f575db24c1b9a7/LICENSE),
  which clarified those license versions. These test assets use the BSD option.
- The alias file comes from the Apache-2.0 licensed Smithy baseline. It is a
  local companion resource rather than an official OpenRPC release asset.
- Unicode identifier tables use the accompanying Unicode license. The generator
  copies that notice into the published package as `UNICODE-LICENSE.txt`.

## Portable pattern qualification

The schema checker fixes ECMA-262 ninth edition, 2018, without flags, including
Annex B. Its primary grammar is [the official edition source](https://github.com/tc39/ecma262/blob/es2018/spec.html),
sections 21.2.1 and B.1.4. Unicode identifier properties are frozen at 10.0.0.
The library checks syntax and early errors; it never matches instance strings.

`mise run build:openrpc-unicode` generates inclusive identifier ranges from the
frozen property data. `mise run check:openrpc-unicode` checks generated bytes and
the copied license without rewriting them. Generator tests prove missing/stale
outputs and tampered inputs fail. Ordinary asset verification includes both
Unicode inputs, with no fetching during checks.

The local 81-case corpus under `tests/openrpc-qualification/` is authored test
data, separate from unchanged upstream assets. `mise run check:openrpc` compares
its accept/reject results with the exact locked
`@eslint-community/regexpp@4.12.2` parser in ECMAScript2018 mode and the MoonBit
checker on all four targets. This development dependency stays outside the
published library. Large exact quantifier bounds also have direct tests that do
not rely on a floating-point syntax oracle.

The adjacent schema-shape corpus uses exact locked `ajv@8.17.1`, with only the
frozen `draft-07-schema.json` registered and format checks disabled. Its positive
and negative cases cover the complete keyword vocabulary. The checker compares
both the independent metaschema outcome and the library outcome on all four
targets. Two named differences are explicit: reference siblings follow draft-07
reference semantics in the library, and large neighboring enum integers remain
distinct despite the oracle's host-number rounding. Both actual outcomes are
checked; neither difference is silently treated as agreement. Full OpenRPC
metaschema/profile qualification remains a separate later story.
