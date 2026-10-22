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
