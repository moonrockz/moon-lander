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
        raise @mediator.MediatorError::rejected("password is too short")
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
    raise @mediator.MediatorError::rejected("unknown user")
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
      "" => raise @mediator.MediatorError::rejected("user is empty")
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
  let error = @mediator.MediatorError::from_publish_errors([None, Some(Locked("ann")), None]).unwrap()
  assert_eq(
    error.message(),
    "Publish failed: 1 of 3 handlers raised an error (position 2)",
  )
}

///|
test "the publish message gives the count and positions of two failures" {
  let error = @mediator.MediatorError::from_publish_errors([None, Some(Locked("ann")), Some(Locked("bo"))]).unwrap()
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
  let error = @mediator.MediatorError::timed_out(@lander_core.TimeLimit::millis(50))
  assert_eq(error.message(), "Request timed out after 50 ms")
}

///|
test "empty and all-success outcomes cannot make PublishFailed" {
  assert_true(@mediator.MediatorError::from_publish_errors([]) is None)
  assert_true(@mediator.MediatorError::from_publish_errors([None]) is None)
  assert_true(@mediator.MediatorError::from_publish_errors([None, None]) is None)
}

///|
test "derived failures include first and last positions with safe access" {
  let outcomes : Array[Error?] = [Some(Locked("first")), None, Some(Locked("last"))]
  guard @mediator.MediatorError::from_publish_errors(outcomes) is Some(error) else {
    fail("expected a publish error")
  }
  guard error is @mediator.PublishFailed(handlers~, failures~) else {
    fail("expected PublishFailed")
  }
  assert_eq(handlers, 3)
  assert_eq(failures.length(), 2)
  assert_true(failures.get(-1) is None)
  assert_true(failures.get(2) is None)
  guard failures.get(0) is Some(first) else { fail("missing first failure") }
  guard failures.get(1) is Some(last) else { fail("missing last failure") }
  assert_eq(first.position, 1)
  assert_eq(last.position, 3)
  assert_true(first.error is Locked("first"))
  assert_true(last.error is Locked("last"))
  assert_eq(error.message(), "Publish failed: 2 of 3 handlers raised an error (positions 1, 3)")
}

///|
test "a one-handler failure has position one and independent storage" {
  let outcomes : Array[Error?] = [Some(Locked("only"))]
  guard @mediator.MediatorError::from_publish_errors(outcomes) is Some(error) else {
    fail("expected a publish error")
  }
  guard error is @mediator.PublishFailed(handlers~, failures~) else {
    fail("expected PublishFailed")
  }
  let before = error.message()
  let copy = failures.to_array()
  copy.clear()
  outcomes[0] = None
  outcomes.clear()
  assert_eq(handlers, 1)
  assert_eq(failures.length(), 1)
  guard failures.get(0) is Some(failure) else { fail("missing failure") }
  assert_eq(failure.position, 1)
  assert_true(failure.error is Locked("only"))
  assert_eq(error.message(), before)
}

///|
test "middleware cannot clear a failure report before it re-raises" {
  let guarded : @mediator.Topic[Unit, Unit] = @mediator.topic((_, _) => {
    raise Locked("only")
  }).use_(@mediator.middleware((next, ctx, ev) => {
    next(ctx, ev) catch {
      @mediator.PublishFailed(failures~, ..) as error => {
        failures.to_array().clear()
        raise error
      }
      other => raise other
    }
  }))
  try guarded.publish((), ()) catch {
    @mediator.PublishFailed(handlers~, failures~) as error => {
      assert_eq(handlers, 1)
      assert_eq(failures.length(), 1)
      assert_eq(error.message(), "Publish failed: 1 of 1 handlers raised an error (position 1)")
    }
    other => fail("unexpected error: \{other}")
  } noraise { _ => fail("expected a failure") }
}

///|
test "timeout construction keeps the smallest and largest core limits" {
  for millis in [1, 2147483647] {
    let limit = @lander_core.TimeLimit::millis(millis)
    let error = @mediator.MediatorError::timed_out(limit)
    guard error is @mediator.TimedOut(after~) else { fail("expected TimedOut") }
    assert_eq(after, limit)
    assert_eq(error.message(), "Request timed out after \{millis} ms")
  }
}
