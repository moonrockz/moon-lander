///|
let local_git_vars : Array[String] = [
  "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
  "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
  "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
  "GIT_SHALLOW_FILE", "GIT_COMMON_DIR",
]

///|
/// Hooks can set Git variables for a different worktree. The source policy uses this root.
fn git_env() -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for name, value in @env.get_env_vars() {
    if !local_git_vars.contains(name.to_upper()) { result[name] = value }
  }
  result
}

///|
async fn git(root : String, args : Array[String]) -> String {
  let (code, stdout, stderr) = @process.collect_output(
    "git", args, cwd=root, extra_env=git_env(), inherit_env=false,
  )
  guard code == 0 else {
    raise @model.Invalid([@model.problem(root, "git \{args.join(" ")}: \{stderr.text()}")])
  }
  stdout.text()
}

///|
/// Add only repository policy to the shared host configuration.
async fn effective_configuration(root : String, tree : @policy.TreePrefix) -> String {
  let file = "\{root}/site/site.json"
  let text = @fs.read_file(file).text()
  let parsed = @model.SiteConfig::parse(file, text)
  for dir in parsed.api {
    guard dir.has_prefix("pkgs/") && dir.split("/").count() == 2 else {
      raise @model.Invalid([@model.problem(file, "api: \{dir} is not a published pkgs module")])
    }
  }
  let plans = git(root, ["ls-files", "--cached", "--others", "--exclude-standard", "--", "docs/superpowers"])
  guard plans.trim().is_empty() else {
    raise @model.Invalid([@model.problem("docs/superpowers/", "agent plans must be excluded from the site: \{plans.trim()}")])
  }
  let ignored = git(root, [
    "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z",
    "--", "docs", "site", "pkgs", "tests",
  ])
  let excluded = parsed.exclude.copy()
  if !excluded.contains("docs/assets") { excluded.push("docs/assets") }
  for path in ignored.split("\u{0}") {
    let path = path.trim_end(chars="/").to_owned()
    if path != "" { excluded.push(path) }
  }
  let value = @json.parse(text)
  guard value is Object(fields) else { abort("SiteConfig parsed a non-object") }
  fields["exclude"] = Json(excluded)
  fields["repo_ref"] = Json(git(root, ["rev-parse", "HEAD"]).trim().to_owned())
  fields["base_path"] = Json(parsed.base_path + tree.text())
  fields["site_url"] = Json(parsed.site_url + tree.text())
  // Configuration is inside the project but outside all discovered source roots.
  let directory = "\{root}/_build/site-input"
  @fs.mkdir(directory, recursive=true, allow_exist=true)
  let path = "\{directory}/site-\{tree.text().replace_all(old="/", new="-")}.json"
  @fs.write_file(path, value.stringify(), create_mode=CreateOrTruncate)
  path
}
