## ADDED Requirements

### Requirement: Branded landing page

The site root SHALL show a landing page that explains Moon-Lander as an
application framework for MoonBit. It MUST include the Moon-Lander mascot,
direct links to the documentation and API index, and links to the guides for
configuration, logging, hosting, mediator and actors.

#### Scenario: Reader enters the site
- **WHEN** a reader opens the site root
- **THEN** the page shows one main heading, the bunny-and-lander artwork, a short framework description, and working links to the documentation, API and package guides

#### Scenario: Reader uses a phone
- **WHEN** the landing page is viewed at 390 CSS pixels wide
- **THEN** the artwork, text, installation instructions and guide links fit without horizontal page scrolling

### Requirement: Landing page installation guidance

The landing page SHALL show a copyable command to add the framework to a MoonBit
project and explain that the individual modules can be selected separately.
It MUST NOT state an obsolete fixed release version or module count.

#### Scenario: Framework installation
- **WHEN** a reader opens the landing page
- **THEN** it shows `moon add moonrockz/moon-lander` as selectable text and links to the package guides for module selection

### Requirement: Smithy color scheme

The landing page and shared documentation shell SHALL use the Smithy indigo and
cool-neutral palette in light and dark modes. Text, controls and focus indicators
MUST remain readable in both modes. The existing system, light and dark theme
selection SHALL apply to both page types.

#### Scenario: Light theme
- **WHEN** a reader selects the light theme on the landing page and opens a documentation page
- **THEN** both pages use the `#f9fafb` page background, `#ffffff` surface, `#111827` text and `#4f46e5` accent

#### Scenario: Dark theme
- **WHEN** a reader selects the dark theme on a documentation page and returns to the landing page
- **THEN** both pages use the `#0f1014` page background, `#17181f` surface, `#e5e7eb` text and `#a5b4fc` accent

#### Scenario: Accessible contrast
- **WHEN** browser acceptance checks inspect the landing page and a documentation page in both themes
- **THEN** normal text and links have at least 4.5:1 contrast and essential control and focus indicators have at least 3:1 contrast against adjacent colors

### Requirement: Project identity assets

Each site page SHALL show the Moon-Lander icon beside the project title in its
home link and declare the Moon-Lander browser favicon. These assets MUST resolve
within the active deployment base and version tree. The home link MUST have a
single accessible project name.

#### Scenario: Project base
- **WHEN** a reader opens a page below `/moon-lander/`
- **THEN** its header icon and favicon resolve below `/moon-lander/` and its brand link opens that tree's home page

#### Scenario: Versioned tree
- **WHEN** a reader opens `/moon-lander/next/docs/`
- **THEN** its header icon and favicon resolve below `/moon-lander/next/` and its brand link opens `/moon-lander/next/`

### Requirement: Site migration preserves routes

The site update SHALL preserve the routes and declared heading and API anchors
of the existing published content for the same source inputs. The search index,
feed, source links and version selection MUST continue to target the active tree.

#### Scenario: Existing package link
- **WHEN** the current notebooks guide and API data are built by the updated site
- **THEN** `/docs/packages/notebooks/` and `/api/moonrockz/notebooks/#CellKind` remain valid below the active base path

#### Scenario: Compatibility comparison
- **WHEN** a migration acceptance check compares the old and new outputs for the same reviewed sources
- **THEN** every old content route and declared heading and API anchor is present in the new output, apart from the landing heading changed by this proposal

## MODIFIED Requirements

### Requirement: Content sources

The build SHALL make pages from these sources only: Markdown and HTML files below
`docs/`, `site/pages/index.html` as the landing page, dated files below
`site/articles/`, the `README.md` or `README.mbt.md` of each package listed in
`site/site.json`, with the READMEs below that package, and the `moon doc` output of
each module directory in the `api` key of `site/site.json`. Files below
`docs/assets/` SHALL be assets, not content pages.

#### Scenario: Package page
- **WHEN** `site/site.json` lists the package `notebooks`
- **THEN** the build makes the page `/docs/packages/notebooks/` from `pkgs/notebooks/README.md`

#### Scenario: Two README kinds in one directory
- **WHEN** a listed package directory has both `README.md` and `README.mbt.md`
- **THEN** the build fails with a message that names the directory and both files

#### Scenario: Brand asset documentation
- **WHEN** `docs/assets/brand/README.md` and `docs/assets/brand/preview.html` exist
- **THEN** they are not discovered as documentation pages or sidebar entries, and their presence does not fail the build

### Requirement: Browser smoke test

`mise run test:site` SHALL run browser checks against the built site. They MUST
check the landing content, branding, themes, search, copy controls, a diagram,
the Design overview status banner, an API item and source link, and the absence
of page errors. The landing and docs navigation MUST work without JavaScript.

#### Scenario: Smoke test passes
- **WHEN** `mise run test:site` runs on a correct build
- **THEN** the browser test passes and the task exits with code zero

#### Scenario: Landing page without JavaScript
- **WHEN** a browser with JavaScript disabled opens the landing page
- **THEN** its artwork, framework description, installation command, package guide links and documentation and API links remain visible and usable

#### Scenario: Missing brand asset
- **WHEN** a built page declares a header icon or favicon whose file is missing
- **THEN** the site check fails and names the missing resource
