///|
test "a builder with one service builds a Host[Unit]" {
  let host : @hosting.Host[Unit] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      ["build"],
    )
    |> @hosting.service(
      @hosting.ServiceName::parse("db"),
      start=_ => (),
      stop=_ => (),
    )
    |> @hosting.build(_ => ())
  ignore(host)
}

///|
test "the factory fixes the services type" {
  let host : @hosting.Host[Array[String]] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      [],
    )
    |> @hosting.service(
      @hosting.ServiceName::parse("log"),
      stop=ctx => ctx.services.push("flushed"),
    )
    |> @hosting.build(_ => [])
  ignore(host)
}

///|
test "a second service with the same name is a fault" {
  let db = @hosting.ServiceName::parse("db")
  let builder : @hosting.HostBuilder[Unit] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      [],
    )
    |> @hosting.service(db)
  let result : Result[@hosting.HostBuilder[Unit], @hosting.HostError] = try
    Ok(builder |> @hosting.service(db))
  catch {
    err => Err(err)
  }
  guard result is Err(@hosting.DuplicateService(name~, existing~) as err) else {
    fail("expected DuplicateService")
  }
  @expect.expect(name).to_equal(db)
  @expect.expect(existing).to_equal(db)
  @expect.expect(err.message()).to_equal(
    "The host already has a service named \"db\"",
  )
}

///|
test "service names that differ only in letter case are duplicates" {
  let builder : @hosting.HostBuilder[Unit] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      [],
    )
    |> @hosting.service(@hosting.ServiceName::parse("Données"))
  for text in ["données", "DONNÉES"] {
    let name = @hosting.ServiceName::parse(text)
    let result : Result[@hosting.HostBuilder[Unit], @hosting.HostError] = try
      Ok(builder |> @hosting.service(name))
    catch {
      err => Err(err)
    }
    guard result is Err(@hosting.DuplicateService(name=got, existing~) as err) else {
      fail("expected DuplicateService for \{text}")
    }
    @expect.expect(got).to_equal(name)
    @expect.expect(existing.to_string()).to_equal("Données")
    @expect.expect(err.message()).to_equal(
      "The host already has a service named \"Données\"; \{text.escape()} differs from it only in letter case",
    )
  }
  ignore(builder |> @hosting.service(@hosting.ServiceName::parse("donnees")))
}

///|
test "case pairs that are not symmetric are duplicates" {
  for
    pair in [
      ("ΟΔΟΣ", "οδος"),
      ("\u{00B5}s", "\u{03BC}s"),
      ("\u{017F}vc", "svc"),
      ("Straße", "STRASSE"),
    ] {
    let (first, second) = pair
    let builder : @hosting.HostBuilder[Unit] = @hosting.builder(
        @hosting.AppName::parse("acme"),
        [],
      )
      |> @hosting.service(@hosting.ServiceName::parse(first))
    let result : Result[@hosting.HostBuilder[Unit], @hosting.HostError] = try
      Ok(builder |> @hosting.service(@hosting.ServiceName::parse(second)))
    catch {
      err => Err(err)
    }
    guard result is Err(@hosting.DuplicateService(..)) else {
      fail("expected DuplicateService for \{first} and \{second}")
    }
  }
}
