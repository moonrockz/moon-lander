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
/// Usage: `check [--root <dir>] [--dir <dir>]`. The root is the repository, `../..` by default. The
/// site directory is `<root>/_site` by default.
async fn main {
  let args = @env.args()
  let root = option(args, "--root", "../..")
  let dir = option(args, "--dir", "\{root}/_site")
  let problems = check_site(root, dir) catch {
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
