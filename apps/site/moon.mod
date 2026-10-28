name = "moonrockz/moon-lander-site"

// Tooling and tests must never publish. The pinned toolchain rejects private publication.
private = true

version = "0.7.0"

import {
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.6",
  "moonbit-community/rabbita@0.16.5",
  "moonbit-community/cmark@0.4.12",
  "bobzhang/beautiful_mermaid@0.2.0",
  "moonrockz/expect@0.6.1",
}

description = "Static docs site generator for Moon-Lander, excluded from publication"

repository = "https://github.com/moonrockz/moon-lander"

license = "Apache-2.0"

readme = "README.md"

preferred_target = "native"
