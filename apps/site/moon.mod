name = "moonrockz/moon-lander-site"

// Tooling and tests must never publish. The pinned toolchain rejects private publication.
private = true

version = "0.8.0"

import {
  "moonrockz/telescope@0.5.1",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.6",
  "bobzhang/beautiful_mermaid@0.2.0",
}

description = "Static docs site generator for Moon-Lander, excluded from publication"

repository = "https://github.com/moonrockz/moon-lander"

license = "Apache-2.0"

readme = "README.md"

preferred_target = "native"
