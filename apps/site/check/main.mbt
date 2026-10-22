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
/// Usage: `check [--root <dir>] [--dir <dir>] [--base <path>] [--api <dir>]`. The root is the
/// repository, `../..` by default. The site directory is `<root>/_site` and the `moon doc` output of the
/// API pages is below `<root>/_build/site-api` by default. `--base` is the base path of the site in the
/// site directory, the `base_path` of `site/site.json` by default. An API item without a docstring
/// gives a warning, not a problem.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let dir = option(args, "--dir", "\{root}/_site")
  let api_dir = option(args, "--api", "\{root}/_build/site-api")
  let warnings = api_warnings(
    api_dir,
    @model.SiteConfig::parse(
      "site/site.json",
      @fs.read_file("\{root}/site/site.json").text(),
    ),
  ) catch {
    @model.Invalid(problems) => problems
    error => [@model.problem(api_dir, "\{error}")]
  }
  for w in warnings {
    println("warning: \{w.render()}")
  }
  let base = if args.contains("--base") {
    Some(option(args, "--base", ""))
  } else {
    None
  }
  let problems = check_site(root, dir, base?) catch {
    @model.Invalid(problems) => problems
    error => [@model.problem(dir, "\{error}")]
  }
  for p in problems {
    eprintln("error: \{p.render()}")
  }
  if problems.length() > 0 {
    eprintln("check: \{problems.length()} problem(s)")
    @sys.exit(1)
  }
  println("check: \{dir} is valid")
}
