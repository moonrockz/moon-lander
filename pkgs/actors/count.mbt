///|
/// The rule of a positive count that an input breaks.
#derive(Eq, Debug)
pub enum CountRule {
  /// The value is zero or less.
  NotPositive
}

///|
pub extend CountRule with Eq::{equal, not_equal}

///|
pub extend CountRule with @debug.Debug::{to_repr}

///|
/// An input that is not a valid mailbox capacity or message count. Only the
/// constructors of `MailboxCapacity` and `MessageCount` make these errors.
#derive(Debug)
pub suberror CountError {
  /// `input` is not a valid mailbox capacity because of `rule`.
  InvalidCapacity(input~ : Int32, rule~ : CountRule)
  /// `input` is not a valid message count because of `rule`.
  InvalidCount(input~ : Int32, rule~ : CountRule)
}

///|
pub extend CountError with @debug.Debug::{to_repr}

///|
/// The largest number of queued messages that a bounded mailbox holds, from 1
/// to the largest `Int`. The in-flight message does not count.
#derive(Eq, Hash, Debug)
pub struct MailboxCapacity {
  priv value : Int32
}

///|
pub extend MailboxCapacity with Eq::{equal, not_equal}

///|
pub extend MailboxCapacity with Hash::{hash, hash_combine}

///|
pub extend MailboxCapacity with @debug.Debug::{to_repr}

///|
/// Make a capacity of `count` queued messages.
pub fn MailboxCapacity::from_int(
  count : Int32,
) -> MailboxCapacity raise CountError {
  guard count > 0 else { raise InvalidCapacity(input=count, rule=NotPositive) }
  { value: count, }
}

///|
/// The default capacity: 128 queued messages.
pub fn MailboxCapacity::default() -> MailboxCapacity {
  { value: 128, }
}

///|
/// The capacity as a count of messages, from 1 to the largest `Int`.
pub fn MailboxCapacity::to_int(self : MailboxCapacity) -> Int32 {
  self.value
}

///|
/// The largest number of messages that a finite receive takes, from 1 to the
/// largest `Int`.
#derive(Eq, Hash, Debug)
pub struct MessageCount {
  priv value : Int32
}

///|
pub extend MessageCount with Eq::{equal, not_equal}

///|
pub extend MessageCount with Hash::{hash, hash_combine}

///|
pub extend MessageCount with @debug.Debug::{to_repr}

///|
/// Make a count of `count` messages.
pub fn MessageCount::from_int(count : Int32) -> MessageCount raise CountError {
  guard count > 0 else { raise InvalidCount(input=count, rule=NotPositive) }
  { value: count, }
}

///|
/// The count as an `Int`, from 1 to the largest `Int`.
pub fn MessageCount::to_int(self : MessageCount) -> Int32 {
  self.value
}
