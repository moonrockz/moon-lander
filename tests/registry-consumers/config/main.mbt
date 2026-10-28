///|
fn main raise {
  let config = @library.build([@library.in_memory_pairs([("probe", @library.string("ready"))])])
  assert_eq(@library.get_text(config, "probe"), "ready")
  let root = @library.FileTreePath::parse("/w")
  let tree = @library.FileTree::new(complete=true)
    .with_listing(root, [{ name: "app.json", kind: File }, { name: "app.toml", kind: File }])
    .with_file(root.child("app.json"), "{workspace:{}, shared:'json', profiles:{active:['metrics']}}")
    .with_file(root.child("app.toml"), "shared='toml'\nretained=true")
  let conventions = @conventions.base("app") |> @conventions.layouts
    |> @conventions.root_policy(WorkspaceFirst(@library.KeyPath::parse("workspace")))
    |> @conventions.member_loading(ExplicitOnly)
    |> @conventions.format_layers(@conventions.FormatLayers::new([
      @conventions.FormatGroup::new([@conventions.Extension::parse("json")]),
      @conventions.FormatGroup::new([@conventions.Extension::parse("toml")]),
    ]))
    |> @conventions.selected_file_policy(Overlay)
    |> @conventions.profiles(@profiles.Policy::new())
  let options = @conventions.DiscoveryOptions::new(config=Explicit("./app.json"))
  let context : @library.LoadContext = { tree, working_dir: Some(root), platform: Some(Linux), env_vars: Map([]), formats: [@toml.format(), @json5.format()] }
  guard conventions.roots(context, options~) is Done(roots) else { fail("complete roots requested I/O") }
  assert_eq(roots.workspace(), Some(root))
  let builder = @library.builder() |> @library.working_dir("/w")
    |> @library.format(@toml.format()) |> @library.format(@json5.format())
    |> @conventions.add(conventions, options~)
  guard @library.load(builder, tree) is Done(layered) else { fail("complete load requested I/O") }
  assert_eq(@library.get_text(layered, "shared"), "json")
  assert_eq(@library.bind(layered, "retained"), true)
  assert_eq(layered.origins(@library.KeyPath::parse("shared"))[0].priority, 325)
  guard layered.profiles() is Resolved(resolution) else { fail("profiles absent") }
  assert_true(resolution.contains(@library.ProfileName::parse("metrics")))
  assert_eq(layered.reports().filter(report => report.path == Some("/w/app.json")).length(), 1)
  println("ok")
}
