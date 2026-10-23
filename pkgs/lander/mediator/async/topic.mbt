///|
/// A typed async topic for one event type. It holds one or more async event
/// handlers and the middleware around them. A topic starts with one handler,
/// so a topic with no handlers is not a value. An event has no reply.
struct Topic[C, Ev] {
  /// The handlers in add order. No function changes this array after the
  /// topic exists.
  handlers : Array[async (C, Ev) -> Unit]
  /// The first item is the outermost step. No function changes this array
  /// after the topic exists.
  middleware : Array[Middleware[C, Ev, Unit]]
}

///|
/// Build an async topic from its first event handler.
pub fn[C, Ev] topic(handle : async (C, Ev) -> Unit) -> Topic[C, Ev] {
  { handlers: [handle], middleware: [] }
}

///|
/// Give a new topic with `handle` after the handlers that the topic has. The
/// topic itself does not change.
pub fn[C, Ev] Topic::add(
  self : Topic[C, Ev],
  handle : async (C, Ev) -> Unit,
) -> Topic[C, Ev] {
  let handlers = self.handlers.copy()
  handlers.push(handle)
  { handlers, middleware: self.middleware }
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
  { handlers: self.handlers, middleware: steps }
}

///|
/// Publish an event with a context value, and run the handlers one at a time.
/// The middleware runs in attach order around the handlers. Each handler
/// starts after the previous one ends, in add order, also after a handler
/// raises. When one or more handlers raise, the publish raises one
/// `@mediator.PublishFailed` after the last handler. A caller cancellation
/// stops the running handler, the remaining handlers do not start, and the
/// cancellation passes out; the failures before it are not reported.
pub async fn[C, Ev] Topic::publish(
  self : Topic[C, Ev],
  ctx : C,
  ev : Ev,
) -> Unit {
  let handlers = self.handlers
  run(
    self.middleware,
    0,
    (c, e) => {
      let failures : Array[@mediator.PublishFailure] = []
      for index, handle in handlers {
        handle(c, e) catch {
          error => failures.push({ position: index + 1, error })
        }
      }
      raise_failures(handlers.length(), failures)
    },
    ctx,
    ev,
  )
}

///|
/// Publish an event with a context value, and run all handlers at the same
/// time. The middleware runs in attach order around the handlers. The publish
/// starts every handler in one task group and returns only after all of them
/// end. A failing handler does not cancel the others. When one or more
/// handlers raise, the publish raises one `@mediator.PublishFailed` with the
/// failures in add order, whatever order the handlers end in. A caller
/// cancellation cancels every handler and passes out.
pub async fn[C, Ev] Topic::publish_concurrent(
  self : Topic[C, Ev],
  ctx : C,
  ev : Ev,
) -> Unit {
  let handlers = self.handlers
  run(
    self.middleware,
    0,
    (c, e) => {
      let slots : Array[Error?] = Array::make(handlers.length(), None)
      @aio.with_task_group(group => {
        for index, handle in handlers {
          group.spawn_bg(() => {
            handle(c, e) catch {
              error => slots[index] = Some(error)
            }
          })
        }
      })
      let failures : Array[@mediator.PublishFailure] = []
      for index, slot in slots {
        if slot is Some(error) {
          failures.push({ position: index + 1, error })
        }
      }
      raise_failures(handlers.length(), failures)
    },
    ctx,
    ev,
  )
}

///|
/// Raise one `PublishFailed` when `failures` is not empty.
fn raise_failures(
  handlers : Int,
  failures : Array[@mediator.PublishFailure],
) -> Unit raise @mediator.MediatorError {
  if !failures.is_empty() {
    raise @mediator.PublishFailed(handlers~, failures~)
  }
}
