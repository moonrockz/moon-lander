///|
/// Command formatting is the only policy here; the public driver owns lifetime.
fn main {
  let options = parse_options(@env.args()[1:].to_owned()) catch {
    InvalidLaunchOptions(format~, problem~) => {
      match format {
        MachineJson => println(usage_document(problem).stringify())
        Human => eprintln("Moonx launcher: " + problem.document().stringify() + "\n" + usage)
      }
      return @sys.exit(2)
    }
  }
  match options.request {
    Help => {
      match options.format {
        MachineJson => println(help_document().stringify())
        Human => println(usage)
      }
    }
    Run(command) => @driver.run(Process(command), completed=outcome => {
      if startup_document(outcome) is Some(document) {
        match options.format {
          MachineJson => println(document.stringify())
          Human => eprintln("Moonx launcher did not start a child: " + document.stringify())
        }
      }
    })
  }
}
