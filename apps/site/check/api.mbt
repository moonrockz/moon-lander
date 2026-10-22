///|
/// The paths below `dir` of the files named `name`, sorted.
async fn files_named(
  dir : String,
  name : String,
  prefix~ : String = "",
) -> Array[String] {
  let out = []
  let base = if prefix == "" { dir } else { "\{dir}/\{prefix}" }
  for entry in @fs.readdir(base, sort=true) {
    let rel = if prefix == "" { entry } else { "\{prefix}/\{entry}" }
    match @fs.kind("\{dir}/\{rel}") {
      Directory => out.append(files_named(dir, name, prefix=rel))
      Regular if entry == name => out.push(rel)
      _ => ()
    }
  }
  out
}

///|
/// A warning for each public API item and method without a docstring, with its package and anchor.
/// The `moon doc` output of each module directory in the `api` key is below `api_dir`, as the build
/// writes it. A module without that output gives one warning. The warnings never fail the check.
async fn api_warnings(
  api_dir : String,
  config : @model.SiteConfig,
) -> Array[@model.Problem] {
  let warnings = []
  for dir in config.api {
    let doc_root = "\{api_dir}/\{dir}/doc"
    if !@fs.exists(doc_root) {
      warnings.push(
        @model.problem(
          "site/site.json",
          "`api` lists `\{dir}`, but \{doc_root} has no `moon doc` output",
        ),
      )
      continue
    }
    for index in files_named(doc_root, "module_index.json") {
      for path in @model.api_index_packages(
          "\{doc_root}/\{index}",
          @fs.read_file("\{doc_root}/\{index}").text(),
        ) {
        let data = "\{doc_root}/\{path}/package_data.json"
        let api = @model.ApiPackage::parse(data, @fs.read_file(data).text())
        for anchor in @model.api_missing_docstrings(api) {
          warnings.push(@model.problem(path, "`#\{anchor}` has no docstring"))
        }
      }
    }
  }
  warnings
}
