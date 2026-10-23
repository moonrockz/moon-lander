///|
struct Login {
  user : String
  password : String
}

///|
suberror LoginError {
  Locked(String)
} derive(Debug)

///|
test "a validation middleware raises Rejected and the handler does not run" {
  let calls = Ref(0)
  let login : @mediator.Sender[Unit, Login, String] = @mediator.sender((_, req) => {
    calls.val += 1
    "welcome " + req.user
  })
  let checked = login.use_(
    @mediator.before((_, req) => {
      if req.password.length() < 8 {
        raise @mediator.Rejected(reason="password is too short")
      }
    }),
  )
  try checked.send((), { user: "ann", password: "hunter2", }) catch {
    @mediator.Rejected(reason~) => assert_eq(reason, "password is too short")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(calls.val, 0)
  assert_eq(
    checked.send((), { user: "ann", password: "correct horse", }),
    "welcome ann",
  )
  assert_eq(calls.val, 1)
}

///|
test "the message holds the reason and no request value" {
  let secret = "hunter2-secret"
  let login : @mediator.Sender[Unit, Login, String] = @mediator.sender((_, _) => {
    raise @mediator.Rejected(reason="unknown user")
  })
  try login.send((), { user: "ann", password: secret, }) catch {
    @mediator.Rejected(_) as error => {
      let text = error.message()
      assert_eq(text, "Request rejected: unknown user")
      assert_false(text.contains(secret))
      assert_false(text.contains("ann"))
    }
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

///|
test "one sender passes MediatorError and an application error out unchanged" {
  let login : @mediator.Sender[Unit, Login, String] = @mediator.sender((_, req) => {
    match req.user {
      "" => raise @mediator.Rejected(reason="user is empty")
      "bo" => raise Locked(req.user)
      user => "welcome " + user
    }
  })
  try login.send((), { user: "", password: "x", }) catch {
    @mediator.Rejected(reason~) => assert_eq(reason, "user is empty")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  try login.send((), { user: "bo", password: "x", }) catch {
    Locked(user) => assert_eq(user, "bo")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

///|
test "the publish message gives the count and position of one failure" {
  let error = @mediator.PublishFailed(handlers=3, failures=[
    { position: 2, error: Locked("ann"), },
  ])
  assert_eq(
    error.message(),
    "Publish failed: 1 of 3 handlers raised an error (position 2)",
  )
}

///|
test "the publish message gives the count and positions of two failures" {
  let error = @mediator.PublishFailed(handlers=3, failures=[
    { position: 2, error: Locked("ann"), },
    { position: 3, error: Locked("bo"), },
  ])
  assert_eq(
    error.message(),
    "Publish failed: 2 of 3 handlers raised an error (positions 2, 3)",
  )
}

///|
struct Signup {
  user : String
  token : String
}

///|
test "the publish message holds no event value and no handler error text" {
  let event_secret = "event-secret-token"
  let error_secret = "handler-secret-key"
  let signed_up : @mediator.Topic[Unit, Signup] = @mediator.topic((_, _) => ())
  let all = signed_up.add((_, ev) => {
    raise Locked(error_secret + ev.user + ev.token)
  })
  try all.publish((), { user: "ann", token: event_secret, }) catch {
    @mediator.PublishFailed(_) as error => {
      let text = error.message()
      assert_eq(
        text, "Publish failed: 1 of 2 handlers raised an error (position 2)",
      )
      assert_false(text.contains(event_secret))
      assert_false(text.contains(error_secret))
      assert_false(text.contains("ann"))
    }
    other => fail("publish raised another error: \{other}")
  } noraise {
    _ => fail("publish did not raise")
  }
}

///|
test "the timeout message gives the limit and nothing else" {
  let error = @mediator.TimedOut(after_ms=50)
  assert_eq(error.message(), "Request timed out after 50 ms")
}
