# Spec Delta

## Purpose

The docs site turns the user docs, articles, package READMEs and the API of the
published packages into a static website for GitHub Pages, with one version of the docs for each
released minor line and one for `main`. It sets the content rules, the client
behavior, the checks and the deployment of that site.

## ADDED Requirements

### Requirement: Static output below the base path

The site build SHALL write one `index.html` file for each route, at the path
`<route>/index.html` below the output directory. Every internal link, script,
stylesheet and image in the output MUST start with the `base_path` of
`site/site.json`, which is `/moon-lander/`.

#### Scenario: Route file
- **WHEN** the build makes the page for the route `/docs/design/overview/`
- **THEN** the output has the file `docs/design/overview/index.html`

#### Scenario: Links use the base path
- **WHEN** a built page links to the route `/articles/`
- **THEN** the `href` value is `/moon-lander/articles/`

### Requirement: Site configuration is checked

The build SHALL read `site/site.json` and MUST fail with a message that names the
file and the key when the configuration is not valid. `base_path` MUST start and
end with `/`.

#### Scenario: Bad base path
- **WHEN** `site/site.json` has `"base_path": "/moon-lander"`
- **THEN** the build fails with a message that names `site/site.json` and `base_path`, and the exit code is not zero

#### Scenario: Unpublished module in the API list
- **WHEN** the `api` key of `site/site.json` lists `apps/site` or `tests`
- **THEN** the build fails with a message that names `site/site.json`, `api` and the directory

### Requirement: Content sources

The build SHALL make pages from these sources only: Markdown and HTML files below
`docs/`, `site/pages/index.html` as the landing page, dated files below
`site/articles/`, the `README.md` or `README.mbt.md` of each package listed in
`site/site.json`, with the READMEs below that package, and the `moon doc` output of
each module directory in the `api` key of `site/site.json`.

#### Scenario: Package page
- **WHEN** `site/site.json` lists the package `notebooks`
- **THEN** the build makes the page `/docs/packages/notebooks/` from `pkgs/notebooks/README.md`

#### Scenario: Two README kinds in one directory
- **WHEN** a listed package directory has both `README.md` and `README.mbt.md`
- **THEN** the build fails with a message that names the directory and both files

### Requirement: Sidebar groups

The `nav` key of `site/site.json` SHALL put the top-level entries of `docs/` into
labelled groups, in the given order. The build MUST fail for a top-level entry
that no item matches, and for an exact item that matches no entry.

#### Scenario: New page not in nav
- **WHEN** an author adds `docs/NEW_PAGE.md` and no `nav` item matches it
- **THEN** the build fails with a message that names `NEW_PAGE.md`

### Requirement: Drafts

A page with `draft: true` in its front matter SHALL be skipped with a warning in a
local build. A main build MUST fail on it.

#### Scenario: Draft in a local build
- **WHEN** a local build reads a page with `draft: true`
- **THEN** the page is not in the output and the build prints a warning that names the file

#### Scenario: Draft in a main build
- **WHEN** the CI build reads a page with `draft: true`
- **THEN** the build fails with a message that names the file

### Requirement: Articles and feed

An article file name SHALL have the form `YYYY-MM-DD-slug.md` or `.html`, with a
real calendar date and a slug of `a`-`z`, `0`-`9` and single `-`. An article MUST
have `title`, `date` and `authors` in its front matter. The build SHALL write the
article at `/articles/<slug>/` and an Atom feed at `/articles/atom.xml`.

#### Scenario: Article route
- **WHEN** `site/articles/2026-11-02-first-host.md` has the date `2026-11-02`
- **THEN** the article is at `/articles/first-host/` and is an entry in `/articles/atom.xml`

#### Scenario: Date does not match
- **WHEN** an article file name has the date `2026-11-02` and its front matter has `date: 2026-11-03`
- **THEN** the build fails with a message that names the file

#### Scenario: Date is not real
- **WHEN** an article file is named `2026-02-30-x.md`
- **THEN** the build fails with a message that names the file

### Requirement: Status marking

A page with `status: proposed` in its front matter SHALL show the banner
"Proposed — not implemented" above its content, and its sidebar link SHALL show a
"Proposed" badge. A `status` value other than `proposed` MUST fail the build.

#### Scenario: Proposed page
- **WHEN** the build makes a page with `status: proposed`
- **THEN** the page shows the banner "Proposed — not implemented" and its sidebar link has the badge "Proposed"

#### Scenario: Unknown status
- **WHEN** a page has `status: draft-ish`
- **THEN** the build fails with a message that names the file and the value

### Requirement: Tables and highlighted code

The build SHALL render Markdown tables as HTML tables. It SHALL highlight a fenced
code block that has a known language, with colors for the light and dark themes.
A fenced block with an unknown language SHALL stay plain and give a warning.

#### Scenario: Known language
- **WHEN** a page has a fenced block with the language `moonbit`, `mbt`, `toml`, `json`, `yaml`, `shell` or `typescript`
- **THEN** the built block has highlight colors for both themes

#### Scenario: Unknown language
- **WHEN** a page has a fenced block with the language `cobol`
- **THEN** the block is plain text and the build prints a warning that names the file and the language

### Requirement: MoonBit examples are compiled

A MoonBit example on the site SHALL come from a `.mbt.md` file that the workspace
tests compile and run. A `moonbit` or `mbt` fence in any other page MUST have the
word `notest` after the language, or the build fails.

#### Scenario: Tested example
- **WHEN** a package `README.mbt.md` has an `mbt check` block
- **THEN** `mise run test` compiles and runs the block, and the site shows it as highlighted MoonBit

#### Scenario: Untested example in docs
- **WHEN** a page below `docs/` has a fence that starts with exactly ```` ```moonbit ````
- **THEN** the build fails with a message that names the file and the line

#### Scenario: Example of a proposed API
- **WHEN** a page below `docs/` has a fence that starts with ```` ```moonbit notest ````
- **THEN** the build shows the block as highlighted MoonBit and does not fail

### Requirement: Diagrams

The build SHALL render each `mermaid` fenced block as an inline SVG in a
`figure.diagram` element. A diagram that does not render MUST fail the build with
the file name and the number of the diagram. The site MUST NOT load a client-side
diagram renderer.

#### Scenario: Diagram renders
- **WHEN** a page has a valid `mermaid` block with `graph LR`
- **THEN** the built page has a `figure.diagram` element with an `svg` child and no `pre.mermaid` element

#### Scenario: Diagram does not render
- **WHEN** a page has a `mermaid` block that the build cannot render
- **THEN** the build fails with a message that names the file and the diagram number

### Requirement: Images

The build SHALL copy each image that a page links with a relative path, and
rewrite the link to the copied file. An image link to a missing file MUST fail the
build.

#### Scenario: SVG figure
- **WHEN** `docs/design/overview.md` links `images/run-order.svg` and the file exists
- **THEN** the output has `docs/design/overview/images/run-order.svg` and the page links to it with the base path

### Requirement: Callouts

The build SHALL render a block quote whose first line is `[!NOTE]`, `[!TIP]`,
`[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` as a callout with that kind and its
label. Other block quotes SHALL stay block quotes.

#### Scenario: Warning callout
- **WHEN** a page has a block quote that starts with `[!WARNING]`
- **THEN** the built page has an `aside` element with the class `callout warning` and the label "Warning"

### Requirement: Layer-stack figure

The build SHALL render a `layers` fenced block as an ordered figure with one layer
for each non-empty line, in the given order, the first line at the top. A line has
the form `name | detail`. A line without `|` MUST fail the build.

#### Scenario: Layer stack
- **WHEN** a page has a `layers` block with the lines `Overrides | --set key=value` and `Defaults | code`
- **THEN** the built page has a `figure.layer-stack` with two layers, "Overrides" first and "Defaults" second

#### Scenario: Bad layer line
- **WHEN** a `layers` block has the line `Overrides`
- **THEN** the build fails with a message that names the file and the line

### Requirement: Links and anchors resolve

The build SHALL turn a relative link to another Markdown file into a site link,
and a relative link to another repository file into a GitHub link. A link to a
missing page or a missing heading anchor MUST fail the build.

#### Scenario: Relative Markdown link
- **WHEN** `docs/WRITING_FOR_THE_SITE.md` links `design/overview.md#the-layer-stack`
- **THEN** the built link is `/moon-lander/docs/design/overview/#the-layer-stack`

#### Scenario: Missing anchor
- **WHEN** a page links `design/overview.md#no-such-heading`
- **THEN** the build fails with a message that names the file and the link

### Requirement: Pages work without JavaScript

Every page SHALL show its full content, its navigation and its links without
JavaScript. Client islands SHALL only add behavior to an empty mount element.

#### Scenario: No JavaScript
- **WHEN** a browser with JavaScript off opens `/moon-lander/docs/`
- **THEN** the page shows the sidebar and the content, and the main navigation links work

### Requirement: Theme

The theme control SHALL cycle through `system`, `light` and `dark`, store the
choice in the browser, and apply the stored choice before the first paint. The
`system` theme MUST follow the color scheme of the operating system.

#### Scenario: Cycle
- **WHEN** a user with no stored choice clicks the theme control three times
- **THEN** the theme is `light`, then `dark`, then `system`, and the control label names each theme

#### Scenario: Stored choice
- **WHEN** the stored choice is `dark` and the user opens another page
- **THEN** the page paints dark from the start

### Requirement: Search

The build SHALL write a search index of the page titles, headings, summaries and
text, and of each API item and method with its name, its package and the first
sentence of its docstring. The search box SHALL load the index on the first key press, show matching
pages, and open a result on a click or on Enter.

#### Scenario: Search result opens
- **WHEN** a user types `layer` in the search box and presses Enter
- **THEN** the browser opens the first result page

#### Scenario: API item result
- **WHEN** a user types `CellKind` in the search box and presses Enter
- **THEN** the browser opens `/moon-lander/api/moonrockz/notebooks/#CellKind`

#### Scenario: No match
- **WHEN** a user types `zzzqqq` in the search box
- **THEN** the results list shows "No results"

### Requirement: Island links navigate

Every link that a client island renders MUST navigate when a user clicks it. A
test SHALL fail when island source code has a link that does not opt out of the
client router link capture.

#### Scenario: Guard test
- **WHEN** an island source file has an anchor without the opt-out
- **THEN** `mise run test` fails and names the file and the line

### Requirement: Islands size budget

The build SHALL measure the gzip size of the island bundle. It MUST fail above
27 KB and SHALL warn above 25 KB.

#### Scenario: Bundle too large
- **WHEN** the gzip size of the island bundle is 28 KB
- **THEN** `mise run build:site` fails with a message that gives the size and the limit

### Requirement: Built site check

`mise run check:site` SHALL check the output directory: every internal link
resolves to a file, every page has a non-empty `<title>`, the Atom feed is
well-formed XML, and no file is below `docs/superpowers/`.

#### Scenario: Broken internal link
- **WHEN** a built page links `/moon-lander/docs/missing/`
- **THEN** `mise run check:site` fails and names the page and the link

### Requirement: Agent planning documents stay off the site

The build SHALL read only files that git tracks or that git does not ignore. A
file below `docs/superpowers/` that the build reads MUST fail the build.

#### Scenario: Locally excluded plans
- **WHEN** `docs/superpowers/` is in `.git/info/exclude` and has files
- **THEN** the build ignores them and passes

#### Scenario: Plan not excluded
- **WHEN** a file below `docs/superpowers/` is tracked or not ignored
- **THEN** the build fails with a message that names the file

### Requirement: Docs tool stays out of the library

UI code SHALL be allowed only in the unpublished module `apps/site`. Workspace
validation MUST fail when another module imports a UI library.

#### Scenario: UI import in the library
- **WHEN** `pkgs/lander/moon.mod` imports `moonbit-community/rabbita`
- **THEN** `mise run validate` fails and names the module

#### Scenario: Workspace targets
- **WHEN** `mise run check` runs with `apps/site` in `moon.work`
- **THEN** the tests and builds for `wasm`, `wasm-gc`, `js` and `native` pass

### Requirement: Site tasks

The mise tasks `build:site`, `dev:site`, `test:site` and `check:site` SHALL run the
site steps. Each task MUST exit with a non-zero code when a step fails.

#### Scenario: Step fails
- **WHEN** the island bundle step fails during `mise run build:site`
- **THEN** the task stops, prints the failed step, and exits with a non-zero code

### Requirement: Local preview

`mise run dev:site` SHALL build the site, serve it below the base path at
`http://127.0.0.1:4173/moon-lander/`, and build it again after a source file
changes. A request for `/x/` SHALL serve `/x/index.html`. A path outside the base
path SHALL redirect to the base path.

#### Scenario: Directory request
- **WHEN** the preview server gets `/moon-lander/docs/`
- **THEN** it answers with the content of `docs/index.html`

#### Scenario: Path outside the base
- **WHEN** the preview server gets `/other/`
- **THEN** it answers with a redirect to `/moon-lander/`

#### Scenario: Path escape
- **WHEN** the preview server gets `/moon-lander/../secret`
- **THEN** it does not serve a file outside the output directory

### Requirement: Browser smoke test

`mise run test:site` SHALL run a browser test against the built site. The test
MUST check the theme cycle, a search result, the copy button of a code block, a
diagram, the status banner of the Design overview, one API page with an item
anchor and a source link, and the absence of page errors.

#### Scenario: Smoke test passes
- **WHEN** `mise run test:site` runs on a correct build
- **THEN** the browser test passes and the task exits with code zero

### Requirement: Deployment

A push to `main` SHALL build, check and test the site, assemble it with the kept
release versions, and deploy it to GitHub Pages. A pull request SHALL build, check and test the site and MUST NOT deploy it.
Only the deploy job MUST have write permissions.

#### Scenario: Pull request
- **WHEN** a pull request changes `docs/`
- **THEN** CI builds, checks and tests the site, `ci-ok` depends on that job, and nothing deploys

#### Scenario: Push to main
- **WHEN** a commit lands on `main`
- **THEN** the site workflow deploys the `main` build at `https://moonrockz.github.io/moon-lander/next/` with the kept release versions

### Requirement: Design overview page

The site SHALL have the page `/docs/design/overview/`, ported from the spec
explainer page. The page MUST be marked `status: proposed` until the hosting and
configuration changes are implemented.

#### Scenario: Overview marked as proposed
- **WHEN** a user opens `/moon-lander/docs/design/overview/`
- **THEN** the page shows the banner "Proposed — not implemented", a layer-stack figure, at least one table and at least one diagram

### Requirement: API data from moon doc

The site build SHALL run `moon doc` in each module directory of the `api` key and
read the `package_data.json` and `module_index.json` output. The `api` key MUST
list only module directories below `pkgs/`. The build MUST NOT parse `.mbti` files.
When the JSON does not have the expected shape, the build MUST fail.

#### Scenario: Format change
- **WHEN** `package_data.json` has no `values` key
- **THEN** the build fails with a message that names the file and the key

#### Scenario: Fixture shape
- **WHEN** `mise run test` runs
- **THEN** a fixture test reads saved `package_data.json` and `module_index.json` output of the pinned moon and passes

### Requirement: API reference pages

The build SHALL write one page for each package in the `moon doc` output at
`/api/<package path>/`. The page SHALL have the sections Types, Errors, Traits,
Type aliases and Values, in that order, and MUST NOT show an empty section. The
methods and impls of an item SHALL be below that item. An item with an empty
docstring SHALL still have an entry.

#### Scenario: Package page
- **WHEN** the build reads the `moon doc` output of `pkgs/notebooks`
- **THEN** the output has `api/moonrockz/notebooks/index.html` with an entry for `CellKind` in the Types section

#### Scenario: Empty section
- **WHEN** a package has no type aliases
- **THEN** its API page has no Type aliases section

### Requirement: API item anchors

Each API item SHALL have the anchor `#<name>` and each method SHALL have the anchor
`#<Type>.<method>`. A duplicate anchor in one API page MUST fail the build.

#### Scenario: Method anchor
- **WHEN** the type `CellKind` has the method `equal`
- **THEN** the page `/moon-lander/api/moonrockz/notebooks/` has the anchors `CellKind` and `CellKind.equal`

### Requirement: API docstrings and signatures

A docstring SHALL render as Markdown with the same rules as other pages. A
signature SHALL render as code. The build SHALL parse the links in a signature and
MUST NOT copy the signature HTML into the page. Each other `<`, `>` and `&` in a
signature SHALL show as text.

#### Scenario: Signature text
- **WHEN** a signature has `-> N?`
- **THEN** the page shows `-> N?` as text in the code

#### Scenario: Unknown markup
- **WHEN** a signature has an `<a>` tag without `href` or without `</a>`
- **THEN** the build fails with a message that names the package and the item

### Requirement: API signature links

The build SHALL rewrite each signature link. A target in the same package SHALL
become `#<item>`. A target in another package on the site SHALL become
`/moon-lander/api/<package path>/#<item>`. A target outside the site SHALL become
plain text.

#### Scenario: Same package
- **WHEN** a signature in `moonrockz/notebooks` links `moonrockz/notebooks#CellKind`
- **THEN** the built link is `#CellKind`

#### Scenario: Package outside the site
- **WHEN** a signature links `moonbitlang/core/builtin#Eq`
- **THEN** the page shows `Eq` as plain text with no link

### Requirement: API source links

Each API item and method SHALL link to its source file on GitHub at the built
commit, at the line in its `loc`.

#### Scenario: Source link
- **WHEN** `CellKind` has `loc.file` `navigation.mbt` and `loc.line` `4` at commit `<sha>`
- **THEN** its source link is `https://github.com/moonrockz/moon-lander/blob/<sha>/pkgs/notebooks/navigation.mbt#L4`

### Requirement: API package index

The build SHALL write the page `/api/` that lists each module and its packages
from `module_index.json`, with a link to each API page and the first paragraph of
the package README as its summary.

#### Scenario: Index
- **WHEN** a user opens `/moon-lander/api/`
- **THEN** the page lists the modules `moonrockz/moon-lander` and `moonrockz/notebooks`, and links `/moon-lander/api/moonrockz/notebooks/`

### Requirement: API links in prose

A Markdown link with the target `api:<package path>`, with an optional
`#<item>` or `#<Type>.<method>`, SHALL become a link to that API page and anchor.
An `api:` link to an unknown package, item or method MUST fail the build.

#### Scenario: Item link
- **WHEN** a page has the link `[CellKind](api:moonrockz/notebooks#CellKind)`
- **THEN** the built link is `/moon-lander/api/moonrockz/notebooks/#CellKind`

#### Scenario: Unknown item
- **WHEN** a page has the link `[x](api:moonrockz/notebooks#NoSuchItem)`
- **THEN** the build fails with a message that names the file and the link

### Requirement: Missing docstring warnings

`mise run check:site` SHALL print a warning for each public API item and method
that has an empty docstring, with its package and anchor. These warnings MUST NOT
fail the check.

#### Scenario: Item without a docstring
- **WHEN** a public value has an empty docstring
- **THEN** `mise run check:site` prints a warning that names the package and the anchor, and exits with code zero

### Requirement: Version trees

A versioned site SHALL have one tree for each kept minor line at `/v/<minor>/`, a
tree for `main` at `/next/`, and the newest release at `/latest/` and at the root.
Every route of a tree SHALL be below the tree base path. A source route named `v`,
`next` or `latest` MUST fail the build.

#### Scenario: Minor line tree
- **WHEN** release `0.1.3` is the newest release of the line `0.1`
- **THEN** its docs are at `/moon-lander/v/0.1/`

#### Scenario: Reserved route
- **WHEN** an author adds a page with the route `/next/`
- **THEN** the build fails with a message that names the file and the route

### Requirement: Version source

The version of a release tree SHALL be the minor line of the root `moon.mod`
version. A build for a minor line that is not the root `moon.mod` line MUST fail.
A patch release SHALL replace the tree of its line.

#### Scenario: Wrong line
- **WHEN** the root `moon.mod` has version `0.2.0` and the build asks for the tree `0.1`
- **THEN** the build fails with a message that names `moon.mod`, `0.2` and `0.1`

#### Scenario: Patch release
- **WHEN** releases `0.1.2` and `0.1.3` both have a site asset
- **THEN** `/moon-lander/v/0.1/` shows the asset of `0.1.3`

### Requirement: Site release asset

A reusable workflow SHALL build the site of one minor line with the base path
`/moon-lander/v/<minor>/`, check it, and give the file `site-<minor>.tar.gz` to its
caller. It MUST NOT create a release, and it MUST have `contents: read` only.

#### Scenario: Asset build
- **WHEN** a workflow calls the asset workflow with the root `moon.mod` version `0.1.0`
- **THEN** the call gives `site-0.1.tar.gz`, and every internal link in it starts with `/moon-lander/v/0.1/`

### Requirement: Versioned deploy

The deploy SHALL download the site asset of the newest release of each minor line
with `contents: read`, add the `main` build at `/next/`, and deploy all trees
together. It MUST NOT rebuild a release from its tag. A missing or corrupt asset
MUST fail the deploy with the release tag.

#### Scenario: Missing asset
- **WHEN** the newest release of a minor line at or above `versions.since` has no `site-<minor>.tar.gz`
- **THEN** the deploy fails with a message that names the release tag, and nothing deploys

### Requirement: Release selection

The deploy SHALL read every release through a paginated API call and MUST NOT depend
on a default result limit. It MUST skip draft releases, prereleases, and releases
whose minor line is below `versions.since` in `site.json`.

#### Scenario: Release before site assets
- **WHEN** `versions.since` is `0.2` and the only release is `v0.1.0`, which has no site asset
- **THEN** the deploy succeeds and the root shows the `main` docs with the pre-release banner

#### Scenario: More than 30 releases
- **WHEN** the repository has 45 releases and the newest release of the line `0.2` is the 40th newest
- **THEN** the assembled site has a `/v/0.2/` tree from that release

### Requirement: Root before the first release

Before the first release at or above `versions.since`, the root SHALL show the `main` build,
and each root and `/next/` page SHALL show the banner "Pre-release docs. No version
is released yet. These pages show `main`." The site MUST NOT have a `/latest/` tree
then.

#### Scenario: No release
- **WHEN** the deploy finds no release
- **THEN** `/moon-lander/` shows the `main` docs with the pre-release banner, and `/moon-lander/latest/` does not exist

### Requirement: Older version banner

Each page of a version that is not the newest release SHALL show a banner that
names its version and the latest version, and links to the same page under
`/latest/` when it exists, or else to `/latest/`. The banner MUST show without
JavaScript.

#### Scenario: Old version page
- **WHEN** the latest release is `0.2` and a user opens a page below `/moon-lander/v/0.1/`
- **THEN** the page shows "You are reading 0.1 docs. The latest is 0.2."

### Requirement: Canonical links

Each page below `/v/`, `/next/` and the root SHALL have a canonical link to the
same page under `/latest/` when that page exists. A page that does not exist under
`/latest/` MUST NOT have a canonical link.

#### Scenario: Page in latest
- **WHEN** `/moon-lander/v/0.1/docs/design/overview/` also exists under `/latest/`
- **THEN** its canonical link is `https://moonrockz.github.io/moon-lander/latest/docs/design/overview/`

### Requirement: Version switcher

The deploy SHALL write `versions.json` at the site root with the latest version,
`next` and each kept version. The switcher island SHALL list them. On a choice, it
SHALL open the current path in the target version when that page exists, or else
the root of the target version.

#### Scenario: Page exists
- **WHEN** a user on `/moon-lander/v/0.2/docs/design/overview/` chooses `0.1` and that page exists in `0.1`
- **THEN** the browser opens `/moon-lander/v/0.1/docs/design/overview/`

#### Scenario: Page missing
- **WHEN** a user on `/moon-lander/v/0.2/api/moonrockz/moon-lander/config/` chooses `0.1` and that page does not exist in `0.1`
- **THEN** the browser opens `/moon-lander/v/0.1/`

### Requirement: Versioned API and search

Each version tree SHALL have the API pages and the search index of its own build.
The search box SHALL load the index of the tree that it is in.

#### Scenario: Search in an old version
- **WHEN** a user searches on a page below `/moon-lander/v/0.1/`
- **THEN** the search loads `/moon-lander/v/0.1/search-index.json`, and each result is below `/moon-lander/v/0.1/`

### Requirement: Version tree check

On an assembled site, `mise run check:site` SHALL check each tree. Every internal
link in a tree MUST start with the base path of that tree. Only canonical links,
banner links and the switcher data MAY leave a tree.

#### Scenario: Link leaves its tree
- **WHEN** a page below `/moon-lander/v/0.1/` links `/moon-lander/v/0.2/docs/`
- **THEN** `mise run check:site` fails and names the page and the link
