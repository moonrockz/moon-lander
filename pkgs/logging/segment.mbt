///|
/// One ordered part of the message text of an event. A renderer uses the
/// segments to show the literal text and the bound values in different styles.
/// The text of all segments, in order, is equal to `LogEvent::message`.
pub(all) enum MessageSegment {
  /// Literal text of the template. A hole that has no property stays here as
  /// its literal text, for example `{Target}`, as `message` shows it.
  Text(String)
  /// A hole with a bound property: the hole name and the JSON value. When a name
  /// occurs in more than one hole, each of these holes holds the first value.
  Value(name~ : String, value~ : Json)
} derive(Eq, Debug)

///|
pub extend MessageSegment with Eq::{equal, not_equal}

///|
pub extend MessageSegment with @debug.Debug::{to_repr}

///|
/// The text of the segment in the message: the literal text, or the value as
/// `message` shows it. A JSON string has no quotes, and each other value is
/// compact JSON.
pub fn MessageSegment::text(self : MessageSegment) -> String {
  match self {
    Text(text) => text
    Value(value~, ..) => render_value(value)
  }
}

///|
/// The message as ordered segments. Two literal parts next to each other join
/// into one `Text` segment. The result is a copy: a change to it, or to a JSON
/// array or object in it, does not change the event.
pub fn LogEvent::segments(self : LogEvent) -> Array[MessageSegment] {
  let segments : Array[MessageSegment] = []
  let text = StringBuilder()
  let flush = () => {
    if !text.is_empty() {
      segments.push(Text(text.to_string()))
      text.reset()
    }
  }
  for part in parse_template(self.template) {
    match part {
      Literal(literal) => text.write_string(literal)
      Hole(name) =>
        match self.find(name) {
          Some(value) => {
            flush()
            segments.push(Value(name~, value=copy_json(value)))
          }
          None => text.write_string("{\{name}}")
        }
    }
  }
  flush()
  segments
}
