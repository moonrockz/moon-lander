name = "moonrockz/moon-lander-tests"

// Tooling and tests must never publish. The pinned toolchain rejects private publication.
private = true

version = "0.11.0"

import {
  "moonbitlang/async@0.22.5",
  "moonrockz/notebooks@0.11.0",
  "moonrockz/moon-lander@0.11.0",
  "moonrockz/moon-lander-core@0.11.0",
  "moonrockz/moon-lander-config@0.11.0",
  "moonrockz/moon-lander-logging@0.11.0",
  "moonrockz/moon-lander-mediator@0.11.0",
  "moonrockz/moon-lander-hosting@0.11.0",
  "moonrockz/moon-lander-moonx@0.11.0",
  "moonrockz/moon-lander-logging-hosting-async@0.11.0",
  "moonrockz/moon-lander-actors@0.11.0",
  "moonrockz/openrpc@0.11.0",
  "moonrockz/sigstore@0.11.0",
  "moonrockz/ion@0.6.0",
  "moonrockz/moonspec@0.11.0",
  "moonrockz/expect@0.6.1",
}

description = "Acceptance tests and domain laws for Moon-Lander, excluded from publication"

license = "Apache-2.0"

readme = "README.md"

preferred_target = "js"
