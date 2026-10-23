///|
/// A typed topic for one event type. It holds one or more event handlers and
/// the middleware around them. A topic starts with one handler, so a topic
/// with no handlers is not a value. An event has no reply.
struct Topic[C, Ev] {
  /// The handlers in add order. No function changes this array after the
  /// topic exists.
  handlers : Array[(C, Ev) -> Unit raise]
  /// The first item is the outermost step. No function changes this array
  /// after the topic exists.
  middleware : Array[Middleware[C, Ev, Unit]]
}

///|
/// Build a topic from its first event handler.
pub fn[C, Ev] topic(handle : (C, Ev) -> Unit raise) -> Topic[C, Ev] {
  { handlers: [handle], middleware: [], }
}

///|
/// Give a new topic with `handle` after the handlers that the topic has. The
/// topic itself does not change.
pub fn[C, Ev] Topic::add(
  self : Topic[C, Ev],
  handle : (C, Ev) -> Unit raise,
) -> Topic[C, Ev] {
  let handlers = self.handlers.copy()
  handlers.push(handle)
  { handlers, middleware: self.middleware, }
}

///|
/// Give a new topic with `middleware` inside the middleware that the topic
/// has. A topic middleware wraps the whole publish: its next step runs all
/// handlers. The first middleware attached is the outermost step. The topic
/// itself does not change.
pub fn[C, Ev] Topic::use_(
  self : Topic[C, Ev],
  middleware : Middleware[C, Ev, Unit],
) -> Topic[C, Ev] {
  let steps = self.middleware.copy()
  steps.push(middleware)
  { handlers: self.handlers, middleware: steps, }
}

///|
/// Publish an event with a context value. The middleware runs in attach order
/// around the handlers. Every handler runs one time, in add order, also after
/// a handler raises. When one or more handlers raise, the publish raises one
/// `MediatorError::PublishFailed` after the last handler, so a topic
/// middleware gets that one combined error from its next step.
pub fn[C, Ev] Topic::publish(
  self : Topic[C, Ev],
  ctx : C,
  ev : Ev,
) -> Unit raise {
  let handlers = self.handlers
  run(
    self.middleware,
    0,
    (c, e) => {
      let failures = []
      for index, handle in handlers {
        handle(c, e) catch {
          error => failures.push({ position: index + 1, error, })
        }
      }
      if !failures.is_empty() {
        raise PublishFailed(handlers=handlers.length(), failures~)
      }
    },
    ctx,
    ev,
  )
}
