///|
/// The value after `name` in `args`, or `default` when `args` has no such option.
fn option(args : Array[String], name : String, default : String) -> String {
  for i in 0..<(args.length() - 1) {
    if args[i] == name {
      return args[i + 1]
    }
  }
  default
}

///|
/// Read every release of the repository with `gh api --paginate`, one release on each line (design
/// D22). `gh` finds the repository from the git remote or `GH_REPO`, and uses `GH_TOKEN`.
async fn read_releases(root : String) -> String {
  let (code, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "api", "--paginate", "repos/{owner}/{repo}/releases", "--jq", releases_filter,
    ],
    cwd=root,
  ) catch {
    error =>
      raise @model.Invalid([@model.problem("gh api", "does not run: \{error}")])
  }
  if code != 0 {
    let detail = stderr.text() catch { _ => "" }
    raise @model.Invalid([
      @model.problem("gh api", "cannot read the releases: \{detail}"),
    ])
  }
  stdout.text() catch { _ => "" }
}

///|
/// Unpack the site asset `archive` of `release` into `to`. A file that does not unpack fails with the
/// release tag.
async fn unpack(
  release : String,
  archive : String,
  to : String,
) -> Unit {
  @fs.mkdir(to, recursive=true, allow_exist=true)
  let (code, _, stderr) = @process.collect_output("tar", [
    "-xzf", archive, "-C", to,
  ]) catch {
    error =>
      raise @model.Invalid([@model.problem(release, "tar does not run: \{error}")])
  }
  if code != 0 {
    let detail = stderr.text() catch { _ => "" }
    raise @model.Invalid([
      @model.problem(release, "the site asset does not unpack: \{detail.trim()}"),
    ])
  }
  if !@fs.exists("\{to}/index.html") {
    raise @model.Invalid([
      @model.problem(release, "the site asset has no `index.html`"),
    ])
  }
}

///|
/// Download the site asset of `release` into `dir` with `gh release download`.
async fn download(
  root : String,
  release : Release,
  dir : String,
) -> String {
  let name = asset_name(minor_of(release.version))
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let (code, _, stderr) = @process.collect_output(
    "gh",
    [
      "release", "download", release.tag, "--pattern", name, "--dir", dir, "--clobber",
    ],
    cwd=root,
  ) catch {
    error =>
      raise @model.Invalid([@model.problem(release.tag, "gh does not run: \{error}")])
  }
  if code != 0 {
    let detail = stderr.text() catch { _ => "" }
    raise @model.Invalid([
      @model.problem(release.tag, "cannot download `\{name}`: \{detail.trim()}"),
    ])
  }
  "\{dir}/\{name}"
}

///|
/// Usage: `assemble [--root <dir>] [--site <dir>] [--releases <file>]`. The root is the repository,
/// `../..` by default, and the site is `<root>/_site`, where the build wrote the `next` tree to
/// `next/`. The releases come from `gh api --paginate`, or from `--releases`, a file in the same
/// format. The site assets are downloaded below `<root>/_build/site-assets/`.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let site = option(args, "--site", "\{root}/_site")
  let releases_file = option(args, "--releases", "")
  let selected = run(root, site, releases_file) catch {
    @model.Invalid(problems) => {
      for p in problems {
        eprintln("error: \{p.render()}")
      }
      eprintln("assemble: \{problems.length()} problem(s)")
      @sys.exit(1)
      []
    }
    error => {
      eprintln("error: \{error}")
      @sys.exit(1)
      []
    }
  }
  if selected.is_empty() {
    println(
      "assemble: no release at or above `versions.since`; the root shows `main` with the pre-release banner",
    )
  } else {
    println("assemble: the latest version is \{minor_of(selected[0].version)}")
  }
}

///|
/// Assemble the site in `site` for the repository at `root`, and return the selected releases.
async fn run(
  root : String,
  site : String,
  releases_file : String,
) -> Array[Release] {
  let assets_dir = "\{root}/_build/site-assets"
  let site_json = @fs.read_file("\{root}/site/site.json").text()
  let config = @model.SiteConfig::parse("site/site.json", site_json)
  let since = versions_since(site_json)
  if !@fs.exists("\{site}/next/index.html") {
    raise @model.Invalid([
      @model.problem(
        site,
        "has no `next` tree; run `mise run build:site -- --main --tree next`",
      ),
    ])
  }
  let text = if releases_file == "" {
    read_releases(root)
  } else {
    @fs.read_file(releases_file).text()
  }
  let selected = select_releases(parse_releases(text), since)
  let missing = missing_assets(selected)
  if !missing.is_empty() {
    raise @model.Invalid(missing)
  }
  for release in selected {
    let line = minor_of(release.version)
    let archive = download(root, release, "\{assets_dir}/\{line}")
    let tree = "\{site}/v/\{line}"
    if @fs.exists(tree) {
      @fs.rmdir(tree, recursive=true)
    }
    unpack(release.tag, archive, tree)
    println("assemble: \{release.tag} gives /v/\{line}/")
  }
  assemble_site(site, {
    base: config.base_path,
    site_url: config.site_url,
    lines: selected.map(release => minor_of(release.version)),
  })
  selected
}
