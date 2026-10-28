///|
/// The opt-in Morphir policy for layered workspaces. The application retains
/// its own member walk; an explicit project selector can still load one member.
pub fn layered_morphir() -> @conventions.Conventions raise @config.ConfigError {
  let json = @conventions.Extension::parse("json")
  let layers = @conventions.FormatLayers::new([
    @conventions.FormatGroup::new([json, @conventions.Extension::parse("json5")],
      supplemental=@conventions.SupplementalFile::new("morphir-workspace.json", json,
        transform=value => @config.fields([("workspace", value)]))),
    @conventions.FormatGroup::new(["yaml", "yml"].map(@conventions.Extension::parse)),
    @conventions.FormatGroup::new([@conventions.Extension::parse("toml")]),
  ])
  morphir()
  |> @conventions.root_policy(WorkspaceFirst(@config.KeyPath::parse("workspace")))
  |> @conventions.member_loading(ExplicitOnly)
  |> @conventions.format_layers(layers)
  |> @conventions.selected_file_policy(Overlay)
  |> @conventions.profiles(@profiles.Policy::new())
}

///|
/// All format alternatives of the opt-in policy. Registration order is separate
/// from precedence: this deliberately registers the highest group first.
pub fn layered_formats() -> Array[@config.Format] {
  [@toml.format(), @yaml.format(), @json5.format()]
}
