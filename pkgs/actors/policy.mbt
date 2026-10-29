///|
/// How many queued messages a mailbox can hold.
pub(all) enum MailboxPolicy {
  /// At most this many queued messages. A send waits while the mailbox is full.
  Bounded(MailboxCapacity)
  /// No limit. The caller selects this policy explicitly.
  Unbounded
} derive(Eq, Debug)

///|
pub extend MailboxPolicy with Eq::{equal, not_equal}

///|
pub extend MailboxPolicy with @debug.Debug::{to_repr}

///|
/// The default policy: bounded at `MailboxCapacity::default()`.
pub fn MailboxPolicy::default() -> MailboxPolicy {
  Bounded(MailboxCapacity::default())
}

///|
/// The result of a send that does not wait.
pub(all) enum Admission {
  /// The mailbox admitted the message.
  Accepted
  /// The bounded mailbox is full. The message was not admitted.
  Full
  /// The mailbox is closed. The message was not admitted.
  Closed
} derive(Eq, Debug)

///|
pub extend Admission with Eq::{equal, not_equal}

///|
pub extend Admission with @debug.Debug::{to_repr}
