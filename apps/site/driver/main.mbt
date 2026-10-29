///|
/// The executable parses arguments once, then runs the shared native host.
async fn main {
  let command = @policy.Command::parse(@env.args()[1:].to_owned()) catch {
    error => {
      eprintln("site: \{error.message()}")
      @sys.exit(2)
      return
    }
  }
  @runtime.run(command) catch {
    @model.Invalid(problems) => {
      for problem in problems { eprintln("error: \{problem.render()}") }
      @sys.exit(1)
    }
    error => {
      eprintln("site: \{error}")
      @sys.exit(1)
    }
  }
}
