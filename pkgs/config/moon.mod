name = "moonrockz/moon-lander-config"

version = "0.6.0"

import {
  "moonrockz/moon-lander-core@0.6.0",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
  "moonbit-community/toml@0.5.0",
  "moonbit-community/yaml@0.0.8",
  "moonrockz/ion@0.6.0",
  "moonrockz/expect@0.6.1",
}

description = "Layered, typed configuration for the Moon-Lander framework"

repository = "https://github.com/moonrockz/moon-lander"

license = "Apache-2.0"

readme = "README.mbt.md"

// The host adapter API exists only on native and js. Canonical interface
// generation needs a backend where that package has code.
preferred_target = "native"
