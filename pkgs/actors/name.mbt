///|
/// The rule of an actor name that an input breaks.
pub enum NameRule {
  /// The text is empty.
  Empty
  /// The text has more than 128 characters.
  TooLong
  /// The first character is not an ASCII letter.
  FirstNotLetter(Char)
  /// A later character is not an ASCII letter, digit, `_`, `-` or `.`.
  InvalidCharacter(Char)
} derive(Eq, Debug)

///|
pub extend NameRule with Eq::{equal, not_equal}

///|
pub extend NameRule with @debug.Debug::{to_repr}

///|
/// An input that is not a valid actor name. Only `ActorName::parse` makes it.
pub suberror NameError {
  /// `input` is not a valid actor name because of `rule`.
  InvalidName(input~ : String, rule~ : NameRule)
} derive(Debug)

///|
pub extend NameError with @debug.Debug::{to_repr}

///|
/// A label that an actor scope can reserve for one actor at a time: 1 to 128
/// ASCII characters, a letter first, then letters, digits, `_`, `-` or `.`.
/// Names are case sensitive and are not trimmed or normalized.
pub struct ActorName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend ActorName with Eq::{equal, not_equal}

///|
pub extend ActorName with Hash::{hash, hash_combine}

///|
pub extend ActorName with @debug.Debug::{to_repr}

///|
/// The longest name in characters.
const MAX_NAME_LENGTH : Int = 128

///|
/// Parse `text` as an actor name.
pub fn ActorName::parse(text : String) -> ActorName raise NameError {
  let chars = text.to_array()
  guard chars.length() > 0 else { raise InvalidName(input=text, rule=Empty) }
  guard chars.length() <= MAX_NAME_LENGTH else {
    raise InvalidName(input=text, rule=TooLong)
  }
  guard is_ascii_letter(chars[0]) else {
    raise InvalidName(input=text, rule=FirstNotLetter(chars[0]))
  }
  for c in chars[1:] {
    guard is_ascii_letter(c) || (c >= '0' && c <= '9') || c is ('_' | '-' | '.') else {
      raise InvalidName(input=text, rule=InvalidCharacter(c))
    }
  }
  { text, }
}

///|
/// The name as it was parsed.
pub fn ActorName::to_string(self : ActorName) -> String {
  self.text
}

///|
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
