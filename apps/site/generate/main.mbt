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
/// Usage: `generate [--root <dir>] [--out <dir>] [--assets <dir>] [--api <dir>] [--tree-path <path>]
/// [--main]`. The root is the repository, `../..` by default. The output is `<root>/_site`, the assets
/// are `<root>/apps/site/assets` and the `moon doc` output is below `<root>/_build/site-api` by default.
/// `--tree-path`, such as `next/` or `v/0.3/`, puts every link below that version tree (design D22).
/// `--main` marks a build for the deployed site: a draft page then fails the build.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let out = option(args, "--out", "\{root}/_site")
  let assets = option(args, "--assets", "\{root}/apps/site/assets")
  let api_dir = option(args, "--api", "\{root}/_build/site-api")
  let tree_path = option(args, "--tree-path", "")
  let main_build = args.contains("--main")
  let warnings = generate(root, out, assets, main_build, api_dir~, tree_path~) catch {
    @model.Invalid(problems) => {
      for p in problems {
        eprintln("error: \{p.render()}")
      }
      eprintln("site: \{problems.length()} problem(s)")
      @sys.exit(1)
      []
    }
    error => {
      eprintln("error: \{error}")
      @sys.exit(1)
      []
    }
  }
  for w in warnings {
    eprintln("warning: \{w.render()}")
  }
  println("site: wrote \{out}")
}
