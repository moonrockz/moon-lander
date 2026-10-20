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
/// Usage: `generate [--root <dir>] [--out <dir>] [--assets <dir>]`. The root is the repository, `../..`
/// by default. The output is `<root>/_site` and the assets are `<root>/apps/site/assets` by default.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let out = option(args, "--out", "\{root}/_site")
  let assets = option(args, "--assets", "\{root}/apps/site/assets")
  generate(root, out, assets) catch {
    @model.Invalid(problems) => {
      for p in problems {
        eprintln("error: \{p.render()}")
      }
      eprintln("site: \{problems.length()} problem(s)")
      @sys.exit(1)
    }
    error => {
      eprintln("error: \{error}")
      @sys.exit(1)
    }
  }
  println("site: wrote \{out}")
}
