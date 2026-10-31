///|
test "omitted and default policies do not encode any protocol" {
  let omit : @policy.PayloadPolicy[() -> Unit] = @policy.PayloadPolicy::omit()
  let default : @policy.PayloadPolicy[() -> Unit] = @policy.PayloadPolicy::default()
  assert_true(omit.apply(() => ()) is None)
  assert_true(default.apply(() => ()) is None)
}

///|
enum IonMessage {
  Sample(@ion.Decimal, @ion.Timestamp)
}

///|
impl @ion.ToIon for IonMessage with to_ion(self) {
  let Sample(amount, time) = self
  @ion.Ion::from_fields([
    @ion.Field("amount", @ion.Ion::decimal(amount)),
    @ion.Field("time", @ion.Ion::timestamp(time)),
  ])
}

///|
test "Ion policy preserves a protocol decimal and timestamp" {
  let amount = @ion.Decimal::parse("12.340")
  let time = @ion.Timestamp::parse("2026-10-31T12:34:56.789Z")
  let policy : @policy.PayloadPolicy[IonMessage] = @policy.PayloadPolicy::ion()
  guard policy.apply(Sample(amount, time)) is Some(payload) else { fail("missing payload") }
  guard payload.kind() is Struct(fields) else { fail("not an Ion struct") }
  assert_eq(fields.length(), 2)
  guard fields[0].value().kind() is Decimal(value) else { fail("lost decimal type") }
  assert_eq(value.to_ion_string(), amount.to_ion_string())
  guard fields[1].value().kind() is Timestamp(value) else { fail("lost timestamp type") }
  assert_eq(value.to_ion_string(), time.to_ion_string())
}

///|
enum JsonMessage {
  Increment(Int)
} derive(ToJson)

///|
test "JSON policy bridges a derived protocol to Ion" {
  let policy : @policy.PayloadPolicy[JsonMessage] = @policy.PayloadPolicy::json()
  let message = Increment(3)
  guard policy.apply(message) is Some(payload) else { fail("missing payload") }
  assert_true(payload.equals(@ion.Ion(ToJson::to_json(message))))
}

///|
enum SecretMessage {
  Authenticate(String, String)
}

///|
test "a custom encoder redacts secrets and runs only when applied" {
  let mut calls = 0
  let policy : @policy.PayloadPolicy[SecretMessage] = @policy.PayloadPolicy::encode(message => {
    calls += 1
    let Authenticate(user, _secret) = message
    @ion.Ion::from_fields([
      @ion.Field("user", @ion.Ion::string(user)),
      @ion.Field("secret", @ion.Ion::string("[redacted]")),
    ])
  })
  assert_eq(calls, 0)
  guard policy.apply(Authenticate("reader", "do-not-log")) is Some(payload) else { fail("missing payload") }
  assert_eq(calls, 1)
  assert_true(payload.equals(@ion.Ion::from_fields([
    @ion.Field("user", @ion.Ion::string("reader")),
    @ion.Field("secret", @ion.Ion::string("[redacted]")),
  ])))
}
