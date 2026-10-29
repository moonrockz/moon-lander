///|
/// A private service with mutable state. Only the service task touches it.
struct Account {
  mut balance : Int
  owner : String
}

///|
suberror Overdrawn {
  Overdrawn(Int)
} derive(Debug)

///|
async test "SVC-1: asks with Int and String results need no enum or cast" {
  @actors.scope(scope => {
    let account = scope.create(Account::{ balance: 10, owner: "ann" })
    let balance : Int = account.ask(a => {
      a.balance += 5
      a.balance
    })
    let owner : String = account.ask(a => a.owner)
    assert_eq(balance, 15)
    assert_eq(owner, "ann")
  })
}

///|
async test "SVC-1: an ask error goes to its caller and keeps prior changes" {
  @actors.scope(scope => {
    let account = scope.create(Account::{ balance: 10, owner: "ann" })
    let failed = try {
      let _ = account.ask(a => {
        a.balance -= 30
        if a.balance < 0 {
          raise Overdrawn(a.balance)
        }
        a.balance
      })
      None
    } catch {
      Overdrawn(balance) => Some(balance)
      _ => None
    }
    assert_eq(failed, Some(-20))
    assert_eq(account.ask(a => a.balance), -20)
  })
}

///|
async test "SVC-1: a tell error fails the service and its scope" {
  let failure = try {
    @actors.scope(scope => {
      let account = scope.create(Account::{ balance: 10, owner: "ann" })
      account.tell(a => raise Overdrawn(a.balance))
      account.join()
    })
    None
  } catch {
    Overdrawn(balance) => Some(balance)
    _ => None
  }
  assert_eq(failure, Some(10))
}
