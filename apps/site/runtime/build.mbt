///|
/// Build using the released shared host and Moon-Lander's fence providers.
async fn build(root : String, config : String, out : String, main_build~ : Bool = false) -> Array[@model.Problem] {
  check_source_policy(root, config, main_build)
  let settings = @host.configuration(config)
  let warnings = @host.build(root, config, out, providers=@providers.registry(), main_build~)
  finish_api_links(out, @policy.BasePath::parse(settings.base_path))
  let problems = @host.check(out, settings.base_path)
  guard problems.is_empty() else { raise @model.Invalid(problems) }
  warnings
}
