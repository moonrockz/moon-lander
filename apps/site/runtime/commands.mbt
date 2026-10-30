///|
/// Run one typed command at the native I/O boundary.
pub async fn run(command : @policy.Command) -> Unit {
  match command {
    Build(root, out, tree, main_build) => {
      let config = effective_configuration(root.text(), tree)
      for warning in build(root.text(), config, out.text(), main_build~) {
        eprintln("warning: \{warning.render()}")
      }
      println("site: wrote \{out.text()} with Telescope \{@host.version}")
    }
    Check(root, out, base) => {
      let config = @host.configuration("\{root.text()}/site/site.json")
      let problems = @host.check(out.text(), base.map(b => b.text()).unwrap_or(config.base_path))
      guard problems.is_empty() else { raise @model.Invalid(problems) }
      println("check: \{out.text()} is valid")
    }
    Serve(root, out, port) => {
      let config = @host.configuration("\{root.text()}/site/site.json")
      println("Site: http://127.0.0.1:\{port.number()}\{config.base_path}")
      @host.serve(out.text(), config.base_path, port.number())
    }
  }
}
