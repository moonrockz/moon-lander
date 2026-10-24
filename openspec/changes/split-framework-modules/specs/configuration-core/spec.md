# Spec Delta

## MODIFIED Requirements

### Requirement: Linked format set

The package `moonrockz/moon-lander-config/formats` SHALL be a virtual package with a
default implementation. Its function `formats()` MUST give the formats that the
program links. The default implementation MUST give the TOML, YAML, JSON5 and Ion
formats in that order. The JSON5 format MUST cover `.json` and `.json5`. The
configuration core package `moonrockz/moon-lander-config` MUST NOT import `formats`.

#### Scenario: Default linked formats

- **WHEN** an application does not override `formats`
- **THEN** `formats()` gives the TOML, YAML, JSON5 and Ion formats, with the extensions `toml`, `yaml`, `yml`, `json`, `json5` and `ion`

### Requirement: Trim formats with one line

The package `moonrockz/moon-lander-config/formats/toml` SHALL implement `formats` with the
TOML format only. An application MUST be able to select it with one `overrides`
entry in its main `moon.pkg` and no code change. The program MUST then link no
parser of the other formats. An application MUST be able to select its own
implementation package in the same way.

#### Scenario: Trim to TOML with one line

- **WHEN** the main `moon.pkg` of an application has `overrides: [ "moonrockz/moon-lander-config/formats/toml" ]`
- **THEN** `formats()` gives only the TOML format, and the application source has no change

#### Scenario: Unused parsers are not linked

- **WHEN** a default application and a trimmed application build on wasm, wasm-gc, js and native
- **THEN** each trimmed output is smaller than the default output of its target and holds no marker string of the YAML, JSON5 or Ion parser

#### Scenario: Own format mix

- **WHEN** an application writes an implementation package of `formats` that gives TOML and YAML, and selects it with `overrides`
- **THEN** `formats()` gives the TOML and YAML formats only
