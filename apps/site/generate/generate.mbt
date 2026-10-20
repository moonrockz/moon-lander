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
/// Build the site of the repository at `root` into `out`, and copy each file of `assets` to
/// `<out>/assets/`. The landing page comes from `site/pages/index.html`.
async fn generate(root : String, out : String, assets : String) -> Unit {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("\{root}/site/site.json").text(),
  )
  let landing = @fs.read_file("\{root}/site/pages/index.html").text()
  let route = "/"
  let page = @views.render(
    { config, route, title: "", description: config.description },
    @views.raw(landing, class="home"),
  )
  write_text("\{out}/\{@model.route_file(route)}", page)
  for name in @fs.readdir(assets, sort=true) {
    copy_file("\{assets}/\{name}", "\{out}/assets/\{name}")
  }
}
