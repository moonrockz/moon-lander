///|
/// A core topic passes errors through; own handlers collect their failures.
priv enum Handlers[C, Ev] {
  Core(@mediator.Topic[C, Ev])
  Own(Array[async (C, Ev) -> Unit])
}

///|
/// A typed async topic for one event type. It holds one or more async event
/// handlers and the middleware around them. A topic starts with one handler,
/// so a topic with no handlers is not a value. An event has no reply.
struct Topic[C, Ev] {
  /// A wrapped core topic or async handlers in add order. No function
  /// changes this value after the topic exists.
  handlers : Handlers[C, Ev]
  /// The first item is the outermost step. No function changes this array
  /// after the topic exists.
  middleware : Array[Middleware[C, Ev, Unit]]
}

///|
/// Build an async topic from its first event handler.
pub fn[C, Ev] topic(handle : async (C, Ev) -> Unit) -> Topic[C, Ev] {
  { handlers: Own([handle]), middleware: [] }
}

///|
/// Wrap a core topic, with its middleware, as an async topic. Both publish
/// operations call the core `publish` and pass its error out unchanged, so a
/// failure is the core `@mediator.PublishFailed` with the positions and the
/// handler count of the core topic. After `add`, the core publish counts as
/// one handler at position 1, and its error is the failure at that position.
pub fn[C, Ev] Topic::from_sync(core : @mediator.Topic[C, Ev]) -> Topic[C, Ev] {
  { handlers: Core(core), middleware: [] }
}

///|
/// Give a new topic with `handle` after the handlers that the topic has. The
/// topic itself does not change.
pub fn[C, Ev] Topic::add(
  self : Topic[C, Ev],
  handle : async (C, Ev) -> Unit,
) -> Topic[C, Ev] {
  let handlers : Array[async (C, Ev) -> Unit] = match self.handlers {
    Core(core) => [(c, e) => core.publish(c, e)]
    Own(handlers) => handlers.copy()
  }
  handlers.push(handle)
  { handlers: Own(handlers), middleware: self.middleware }
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
  let handlers = match self.handlers {
    Core(core) => return run(self.middleware, 0, (c, e) => core.publish(c, e), ctx, ev)
    Own(handlers) => handlers
  }
  run(
    self.middleware,
    0,
    (c, e) => {
      let slots : Array[Error?] = Array::make(handlers.length(), None)
      for index, handle in handlers {
        stop_if_cancelled()
        handle(c, e) catch {
          error => slots[index] = Some(error)
        }
      }
      stop_if_cancelled()
      raise_failures(slots)
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
  let handlers = match self.handlers {
    Core(core) => return run(self.middleware, 0, (c, e) => core.publish(c, e), ctx, ev)
    Own(handlers) => handlers
  }
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
      raise_failures(slots)
    },
    ctx,
    ev,
  )
}

///|
/// End the current task when the caller cancels it. A handler can raise an
/// ordinary error after a cancellation, for example from a protected cleanup,
/// and the `catch` of the loop takes that error, so the loop checks for the
/// cancellation itself: no later handler starts and no `PublishFailed` hides
/// the cancellation.
async fn stop_if_cancelled() -> Unit {
  if @aio.is_being_cancelled() {
    @aio.pause()
  }
}

///|
/// Raise a derived publish error when at least one handler failed.
fn raise_failures(errors : Array[Error?]) -> Unit raise @mediator.MediatorError {
  if @mediator.MediatorError::from_publish_errors(errors) is Some(error) {
    raise error
  }
}
