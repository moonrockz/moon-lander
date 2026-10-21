///|
/// Order by code unit: the pinned `String::compare` orders by length first.
fn compare_units(a : String, b : String) -> Int32 {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// Every regular file below `root`, as sorted paths relative to `root` with `/`.
async fn list_files(root : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let dir = if prefix == "" { root } else { "\{root}/\{prefix}" }
  let names = @fs.readdir(dir)
  names.sort_by(compare_units)
  for name in names {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{root}/\{rel}") {
      Directory => out.append(list_files(root, prefix=rel))
      Regular => out.push(rel)
      _ => ()
    }
  }
  out.sort_by(compare_units)
  out
}

///|
/// The variables that make git use one repository, from
/// `git rev-parse --local-env-vars`. Git sets some of them for hooks.
let local_git_vars : Array[String] = [
  "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
  "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
  "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
  "GIT_SHALLOW_FILE", "GIT_COMMON_DIR",
]

///|
/// The environment of this process without `local_git_vars`, so that a child
/// git finds the repository from its working directory. Use it with
/// `inherit_env=false`.
fn git_env() -> Map[String, String] {
  let env : Map[String, String] = Map([])
  for name, value in @env.get_env_vars() {
    if !local_git_vars.contains(name.to_upper()) {
      env[name] = value
    }
  }
  env
}

///|
/// Repository files below `root`: tracked and untracked, without ignored files.
async fn repository_files(root : String) -> Array[String] raise @model.Invalid {
  let (code, stdout, stderr) = @process.collect_output(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard"],
    extra_env=git_env(),
    inherit_env=false,
    cwd=root,
  ) catch {
    error =>
      raise @model.Invalid([@model.problem(root, "git does not run: \{error}")])
  }
  if code != 0 {
    let detail = stderr.text() catch { _ => "" }
    raise @model.Invalid([
      @model.problem(root, "git ls-files failed: \{detail}"),
    ])
  }
  let text = stdout.text() catch { _ => "" }
  text.split("\n").filter(l => l != "").map(l => l.to_owned()).collect()
}

///|
async fn write_text(path : String, text : String) -> Unit {
  match path.rev_find("/") {
    Some(i) => @fs.mkdir(path[:i].to_owned(), recursive=true, allow_exist=true)
    None => ()
  }
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async fn copy_file(from : String, to : String) -> Unit {
  match to.rev_find("/") {
    Some(i) => @fs.mkdir(to[:i].to_owned(), recursive=true, allow_exist=true)
    None => ()
  }
  @fs.write_file(to, @fs.read_file(from).binary(), create_mode=CreateOrTruncate)
}

///|
/// Build the site of the repository at `root` into `out`, and copy each file below `assets_dir` to
/// `<out>/assets/`. Returns the warnings.
async fn generate(
  root : String,
  out : String,
  assets_dir : String,
  main_build : Bool,
) -> Array[@model.Problem] {
  let config_path = "\{root}/site/site.json"
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file(config_path).text(),
  )
  let sources = []
  for path in repository_files(root) {
    let text = if @site.needs_text(path, config) {
      Some(@fs.read_file("\{root}/\{path}").text())
    } else {
      None
    }
    sources.push(@site.SourceFile::{ path, text, })
  }
  let built = @site.build(config, sources, main_build~)
  for output in built.outputs {
    match output {
      Text(path, text) => write_text("\{out}/\{path}", text)
      Copy(path, from) => copy_file("\{root}/\{from}", "\{out}/\{path}")
    }
  }
  for name in list_files(assets_dir) {
    copy_file("\{assets_dir}/\{name}", "\{out}/assets/\{name}")
  }
  built.warnings
}
