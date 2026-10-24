# Spec Delta

## MODIFIED Requirements

### Requirement: API package index

The build SHALL write the page `/api/` that lists each module and its packages
from `module_index.json`, with a link to each API page and the first paragraph of
the package README as its summary.

#### Scenario: Index
- **WHEN** a user opens `/moon-lander/api/`
- **THEN** the page lists the modules `moonrockz/moon-lander`, `moonrockz/moon-lander-core`, `moonrockz/moon-lander-config`, `moonrockz/moon-lander-mediator`, `moonrockz/moon-lander-hosting`, `moonrockz/notebooks` and `moonrockz/openrpc`, and links `/moon-lander/api/moonrockz/moon-lander-config/` and `/moon-lander/api/moonrockz/notebooks/`
