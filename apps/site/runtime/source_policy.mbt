///|
/// Compiled examples and main-build draft rejection are consumer policy.
async fn check_source_policy(root : String, configuration : String, main_build : Bool) -> Unit {
  let config = @host.configuration(configuration)
  let visible = git(root, ["ls-files", "--cached", "--others", "--exclude-standard", "-z"])
  // Join with the input root; compare canonical paths using their native separator.
  let canonical_root = @fs.realpath(root)
  let separator = if @async.platform is Windows { "\\" } else { "/" }
  let prefix = if canonical_root.has_suffix(separator) {
    canonical_root
  } else {
    canonical_root + separator
  }
  let problems = []
  for path in visible.split("\u{0}") {
    let path = path.to_owned()
    if !config.includes(path) || !@site.needs_text(path, config) { continue }
    let source = "\{root}/\{path}"
    if !@fs.exists(source) { continue }
    let real = @fs.realpath(source)
    guard real.has_prefix(prefix) && @fs.kind(real) is Regular else {
      raise @model.Invalid([@model.problem(path, "source must be a regular file inside the project")])
    }
    let front = @content.parse_front_matter(path, @fs.read_file(real).text())
    if main_build && front.flag("draft") {
      problems.push(@model.problem(path, "draft page is not allowed in a main build"))
    }
    if path.has_suffix(".md") && !path.has_suffix(".mbt.md") {
      problems.append(@content.check_moonbit_fences(path, front.body, first_line=front.body_line))
    }
  }
  guard problems.is_empty() else { raise @model.Invalid(problems) }
}
