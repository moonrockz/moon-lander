///|
/// The `moon doc` output of one module in the `api` key of `site.json`.
pub(all) struct ApiModule {
  /// The module directory, such as `pkgs/notebooks`.
  dir : String
  /// The module name, such as `moonrockz/notebooks`.
  name : String
  /// The packages of the module, in the order of `module_index.json`.
  packages : Array[@model.ApiPackage]
  /// The `README.md` text of each package path that has one in the `moon doc` output.
  readmes : Map[String, String]
}

///|
/// The input of the API pages: the built commit and the modules.
pub(all) struct ApiSite {
  commit : String
  modules : Array[ApiModule]
}

///|
/// No API pages.
pub let no_api : ApiSite = { commit: "", modules: [] }

///|
/// The package paths that have an API page.
pub fn ApiSite::package_paths(self : ApiSite) -> Array[String] {
  let out = []
  for m in self.modules {
    for p in m.packages {
      out.push(p.path)
    }
  }
  out
}

///|
/// The sidebar of the API pages: the index, then each module with its packages.
fn api_nav(site : ApiSite) -> Array[@model.NavItem] {
  let items : Array[@model.NavItem] = [
    { route: "/api/", title: "Overview", depth: 0, proposed: false },
  ]
  for m in site.modules {
    items.push({ route: "", title: m.name, depth: 0, proposed: false })
    for p in m.packages {
      items.push({
        route: @model.api_route(p.path),
        title: package_title(m.name, p.path),
        depth: 1,
        proposed: false,
      })
    }
  }
  items
}

///|
/// The sidebar title of a package: its path below the module, or the module name for the root
/// package.
fn package_title(module_name : String, path : String) -> String {
  if path.has_prefix(module_name + "/") {
    path[module_name.length() + 1:].to_owned()
  } else {
    path
  }
}

///|
/// A docstring as Markdown: without the leading newline, and without the one space that `moon doc`
/// keeps at the start of each line after `///`.
fn docstring_source(docstring : String) -> String {
  let text = if docstring.has_prefix("\n") {
    docstring[1:].to_owned()
  } else {
    docstring
  }
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  if lines.iter().all(l => l == "" || l.has_prefix(" ")) {
    lines.map(l => if l == "" { l } else { l[1:].to_owned() }).join("\n")
  } else {
    text
  }
}

///|
/// The docstring as HTML, through the Markdown rules and the building-block passes of other pages.
fn docstring_html(
  file : String,
  docstring : String,
  problems : Array[@model.Problem],
) -> String {
  let source = docstring_source(docstring)
  if source.trim() == "" {
    return ""
  }
  let doc = @content.render_markdown(file, source) catch {
    @model.Invalid(found) => {
      problems.append(found)
      return ""
    }
  }
  let mermaid = @content.render_mermaid_blocks(file, doc.html)
  problems.append(mermaid.problems)
  let layers = @content.render_layers(file, mermaid.html)
  problems.append(layers.problems)
  "<div class=\"api-doc\">" + @content.render_callouts(layers.html) + "</div>"
}

///|
/// What one API page needs to render a signature and a source link.
priv struct ApiContext {
  config : @model.SiteConfig
  site : ApiSite
  site_packages : Array[String]
  api_module : ApiModule
  package_path : String
  problems : Array[@model.Problem]
}

///|
/// The signature as escaped code with the links of design D21. The raw signature HTML never goes into
/// the page.
fn ApiContext::signature(
  self : ApiContext,
  anchor : String,
  signature : String,
) -> String {
  let parts = match @model.parse_signature(signature) {
    Ok(parts) => parts
    Err(reason) => {
      self.problems.push(
        @model.problem(
          self.package_path,
          "the signature of `\{anchor}` is not valid: \{reason}",
        ),
      )
      []
    }
  }
  let out = StringBuilder()
  out.write_string("<pre class=\"api-signature\"><code>")
  for part in parts {
    match part {
      Text(text) => out.write_string(@content.escape(text))
      Link(target, text) =>
        match
          @model.api_link(
            target,
            current=self.package_path,
            site_packages=self.site_packages,
            base_path=self.config.base_path,
          ) {
          Some(href) =>
            out.write_string(
              "<a href=\"\{@content.escape(href)}\">\{@content.escape(text)}</a>",
            )
          None => out.write_string(@content.escape(text))
        }
    }
  }
  out.write_string("</code></pre>")
  out.to_string()
}

///|
/// One entry: the heading with the anchor, the signature, the docstring and the source link.
fn ApiContext::entry(
  self : ApiContext,
  out : StringBuilder,
  anchor : String,
  title : String,
  entry : @model.ApiEntry,
  level~ : Int32,
) -> Unit {
  let url = @model.api_source_url(
    repo_url=self.config.repo_url,
    commit=self.site.commit,
    module_dir=self.api_module.dir,
    module_name=self.api_module.name,
    entry.loc,
  )
  out.write_string(
    "<h\{level} id=\"\{@content.escape(anchor)}\" class=\"api-name\"><code>\{@content.escape(title)}</code></h\{level}>",
  )
  out.write_string(self.signature(anchor, entry.signature))
  out.write_string(
    docstring_html(
      "\{self.package_path}#\{anchor}",
      entry.docstring,
      self.problems,
    ),
  )
  out.write_string(
    "<p class=\"api-source\"><a href=\"\{@content.escape(url)}\">Source</a></p>",
  )
}

///|
/// An item with its methods and its trait implementations below it. Below a trait, each
/// implementation names its type.
fn ApiContext::item(
  self : ApiContext,
  out : StringBuilder,
  item : @model.ApiItem,
  is_trait~ : Bool = false,
) -> Unit {
  let name = item.entry.name
  out.write_string("<section class=\"api-item\">")
  self.entry(out, name, name, item.entry, level=3)
  for m in item.methods {
    self.entry(
      out,
      @model.api_method_anchor(name, m.name),
      "\{name}::\{m.name}",
      m,
      level=4,
    )
  }
  for i in item.impls {
    out.write_string(
      "<p class=\"api-impl\">impl <code>\{@content.escape(i.trait_name)}</code> for <code>\{@content.escape(i.self_type)}</code></p>",
    )
    let via = if is_trait { i.self_type } else { i.trait_name }
    for m in i.methods {
      self.entry(
        out,
        @model.api_method_anchor(name, m.name, via~),
        "\{i.trait_name}::\{m.name}",
        m,
        level=4,
      )
    }
  }
  out.write_string("</section>")
}

///|
/// One section of an API page.
priv struct ApiSection {
  id : String
  title : String
  items : Array[@model.ApiItem]
  entries : Array[@model.ApiEntry]
  /// The items are traits, so each implementation names its type.
  traits : Bool
}

///|
/// The sections of an API page, in order.
fn api_sections(api : @model.ApiPackage) -> Array[ApiSection] {
  [
    { id: "api-types", title: "Types", items: api.types, entries: [], traits: false },
    { id: "api-errors", title: "Errors", items: api.errors, entries: [], traits: false },
    { id: "api-traits", title: "Traits", items: api.traits, entries: [], traits: true },
    {
      id: "api-type-aliases",
      title: "Type aliases",
      items: [],
      entries: api.aliases,
      traits: false,
    },
    { id: "api-values", title: "Values", items: [], entries: api.values, traits: false },
  ]
}

///|
/// The body of the API page of `api` and its "On this page" rail. A section with no entries is not
/// shown.
fn api_page_body(
  ctx : ApiContext,
  api : @model.ApiPackage,
) -> (String, Array[@model.TocEntry]) {
  let out = StringBuilder()
  let toc : Array[@model.TocEntry] = []
  out.write_string(
    "<h1 class=\"api-title\"><code>\{@content.escape(api.path)}</code></h1>",
  )
  if ctx.api_module.readmes.get(api.path) is Some(readme) &&
    readme_summary(readme) is Some(summary) {
    out.write_string("<p class=\"api-summary\">\{@content.escape(summary)}</p>")
  }
  for section in api_sections(api) {
    if section.items.is_empty() && section.entries.is_empty() {
      continue
    }
    toc.push({ id: section.id, text: section.title, depth: 0 })
    out.write_string("<h2 id=\"\{section.id}\">\{section.title}</h2>")
    for item in section.items {
      ctx.item(out, item, is_trait=section.traits)
    }
    for entry in section.entries {
      out.write_string("<section class=\"api-item\">")
      ctx.entry(out, entry.name, entry.name, entry, level=3)
      out.write_string("</section>")
    }
  }
  (out.to_string(), toc)
}

///|
/// The first paragraph of a README as plain text, or `None` when it has none.
fn readme_summary(readme : String) -> String? {
  let doc = @content.render_markdown("README.md", readme) catch { _ => return None }
  if doc.summary == "" {
    None
  } else {
    Some(doc.summary)
  }
}

///|
/// The body of `/api/`: each module and its packages, with the README summary of each package.
fn api_index_body(config : @model.SiteConfig, site : ApiSite) -> String {
  let out = StringBuilder()
  out.write_string("<h1 id=\"api\">API reference</h1>")
  out.write_string(
    "<p>The public API of each published module, made from the <code>moon doc</code> output of this build.</p>",
  )
  for m in site.modules {
    out.write_string("<h2>\{@content.escape(m.name)}</h2>")
    out.write_string(
      "<table class=\"api-index\"><thead><tr><th>Package</th><th>Summary</th></tr></thead><tbody>",
    )
    for p in m.packages {
      let href = config.href(@model.api_route(p.path))
      let summary = match m.readmes.get(p.path) {
        Some(readme) => readme_summary(readme).unwrap_or("")
        None => ""
      }
      out.write_string(
        "<tr><td><a href=\"\{@content.escape(href)}\"><code>\{@content.escape(p.path)}</code></a></td><td>\{@content.escape(summary)}</td></tr>",
      )
    }
    out.write_string("</tbody></table>")
  }
  @content.analyse_html(out.to_string()).html
}

///|
/// Each anchor that is in `ids` more than once.
fn duplicates(ids : Array[String]) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let out = []
  for id in ids {
    if seen.contains(id) {
      if !out.contains(id) {
        out.push(id)
      }
    } else {
      seen.set(id, true)
    }
  }
  out
}

///|
/// The API pages: `/api/` and one page for each package. Raises every problem together: a signature
/// with unknown markup, a docstring that does not render, or a duplicate anchor in one page.
pub async fn api_outputs(
  config : @model.SiteConfig,
  site : ApiSite,
) -> Array[Output] {
  if site.modules.is_empty() {
    return []
  }
  let problems : Array[@model.Problem] = []
  let site_packages = site.package_paths()
  let nav = api_nav(site)
  let outputs : Array[Output] = []
  for m in site.modules {
    for api in m.packages {
      let ctx : ApiContext = {
        config,
        site,
        site_packages,
        api_module: m,
        package_path: api.path,
        problems,
      }
      let (body, toc) = api_page_body(ctx, api)
      for id in duplicates(@content.ids_in(body)) {
        problems.push(
          @model.problem(api.path, "the API page has the anchor `#\{id}` more than once"),
        )
      }
      let route = @model.api_route(api.path)
      let meta : @views.PageMeta = {
        config,
        route,
        title: api.path,
        description: "The API of the MoonBit package \{api.path}",
        section: Api,
      }
      outputs.push(
        Text(
          @model.route_file(route),
          @views.render(meta, @views.docs_page(meta, nav, body, None, toc~)),
        ),
      )
    }
  }
  let index : @views.PageMeta = {
    config,
    route: "/api/",
    title: "API reference",
    description: "The API of the published Moon-Lander modules",
    section: Api,
  }
  outputs.push(
    Text(
      "api/index.html",
      @views.render(
        index,
        @views.docs_page(index, nav, api_index_body(config, site), None),
      ),
    ),
  )
  if problems.length() > 0 {
    raise @model.Invalid(problems)
  }
  outputs
}
