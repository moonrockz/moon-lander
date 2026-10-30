///|
test "launcher stops parsing options at executable or delimiter" {
  for input in [["--json", "--", "node", "", "--help", "--json", "é🙂"], ["--json", "node", "", "--help", "--json", "é🙂"]] {
    let options = parse_options(input)
    assert_true(options.format is MachineJson)
    guard options.request is Run(command) else { fail("Expected a command") }
    assert_eq(command.executable().to_string(), "node")
    assert_eq(command.arguments().to_array(), ["", "--help", "--json", "é🙂"])
  }
  let options = parse_options(["node", "--json"])
  assert_true(options.format is Human)
  let options = parse_options(["--", "-node", "--json"])
  guard options.request is Run(command) else { fail("Expected literal executable") }
  assert_eq(command.executable().to_string(), "-node")
}

///|
test "launcher help never requires or starts an executable" {
  for input in [["--help", "--json"], ["--json", "-h"]] {
    let options = parse_options(input)
    assert_true(options.request is Help)
    assert_true(options.format is MachineJson)
  }
  assert_eq(@json.parse(help_document().stringify()), help_document())
  assert_true(help_document() is { "schema_version": Number(1, ..), "kind": String("help"), .. })
}

///|
test "launcher usage errors retain format and typed input rule" {
  for input in [[], ["--"], ["--json"]] {
    try parse_options(input) catch {
      InvalidLaunchOptions(format~, problem=MissingExecutable) => {
        assert_true(if input == ["--json"] { format is MachineJson } else { format is Human })
      }
      _ => fail("Expected missing executable")
    } noraise { _ => fail("Accepted a missing executable") }
  }
  try parse_options(["--unknown", "--json", "--", "node"]) catch {
    InvalidLaunchOptions(format=MachineJson, problem=UnknownOption(input)) => assert_eq(input, "--unknown")
    _ => fail("Lost unknown launcher option or JSON mode")
  } noraise { _ => fail("Accepted unknown launcher option") }
  try parse_options([""]) catch {
    InvalidLaunchOptions(problem=Executable(@moonx.ExecutableError::InvalidExecutable(input="", rule=Empty)), ..) => ()
    _ => fail("Expected typed empty executable")
  } noraise { _ => fail("Accepted empty executable") }
  try parse_options(["node", "a\u{0}b"]) catch {
    InvalidLaunchOptions(problem=Arguments(@moonx.ArgumentsError::ArgumentContainsNul(input="a\u{0}b", index=0)), ..) => ()
    _ => fail("Expected typed NUL argument")
  } noraise { _ => fail("Accepted NUL argument") }
}

///|
test "launcher startup document never claims ownership after child startup" {
  for result in [
    @moonx.LaunchResult::Started(Exited(@moonx.ProcessStatus::success())),
    Started(Stopped(cause=Signal(Interrupt), status=@moonx.ProcessStatus::from_bits(137U), force_requested=true)),
    Started(Failed(Failure("wait failure"))),
  ] {
    assert_true(startup_document(@moonx.LaunchOutcome::new(result, @moonx.ProcessStatus::failure(), [])) is None)
  }
}

///|
test "launcher not-started report preserves cancellation and Windows status bits" {
  let outcome = @moonx.LaunchOutcome::new(NotStarted(Cancelled(Signal(Break))), @moonx.ProcessStatus::from_bits(0xc000013aU), [])
  let document = startup_document(outcome).unwrap()
  assert_true(document is { "kind": String("not-started"), "exit_status": Number(3221225786, ..),
    "reason": { "kind": String("signal"), "signal": String("SIGBREAK"), .. }, .. })
  let missing = @moonx.LaunchOutcome::new(NotStarted(Failed(NodeMissing(executable=@moonx.Executable::node(), cause=Failure("missing")))), @moonx.ProcessStatus::failure(), [])
  assert_true(startup_document(missing).unwrap() is { "reason": { "kind": String("node-missing"), .. }, .. })
  assert_true(usage_document(MissingExecutable) is { "kind": String("usage-error"), "exit_status": Number(2, ..), .. })
}
