# moonrockz/moon-lander-hosting

The host of a Moon-Lander application. A host builder holds the application
name, the arguments, the hosted services and a services factory. `build` gives a
`Host`, and `run` starts the services, runs the command and stops the services in
a known order, with a clear exit code. This is the first slice of the change
`add-host-lifecycle`; arguments, lifecycle events, signals and configuration
come next.

Import the root package with an explicit alias, because the module name has `-`
in it. The application name comes from `moonrockz/moon-lander-core`:

```moonbit notest
///|
import {
  "moonrockz/moon-lander-core" @lander_core,
  "moonrockz/moon-lander-hosting" @hosting,
}
```

The module `moonrockz/moon-lander` gives the batteries-included entry
`@lander.cli`. This module gives the bare entry `@hosting.builder`:

```mbt check
///|
test "build a host with one service" {
  let log = []
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder(["greet"])
    |> @hosting.service(
      "greeter",
      start=_ => log.push("greeter started"),
      stop=_ => log.push("greeter stopped"),
    )
    |> @hosting.build(_ => ())
  ignore(host)
  // The build runs no hook.
  assert_eq(log, [])
}
```

| Package | Targets | Content |
| --- | --- | --- |
| `moonrockz/moon-lander-hosting` (`@hosting`) | all; `run` on `native` and `js` | Builder, hosted services, `Host[S]`, `run`, `ServiceName`, `ExitCode` and `HostError` |
| `moonrockz/moon-lander-hosting/console` (`@console`) | `native` | The C signal stub for SIGINT, SIGTERM and SIGQUIT, and the Windows console events |

The [`moonrockz/moon-lander` guide](../lander/README.mbt.md) shows the full
pipeline, the name and exit-code rules, and `run`.
