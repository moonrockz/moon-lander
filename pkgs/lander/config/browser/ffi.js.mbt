///|
pub using @js_async {type AbortSignal, type AbortController}

///|
#external
priv type BrowserAdapter

///|
#external
priv type Reply

///|
let adapter : BrowserAdapter = browser_adapter()

///|
extern "js" fn BrowserAdapter::supported(self : BrowserAdapter) -> Bool =
  #|adapter => adapter.supported()

///|
extern "js" fn BrowserAdapter::normalize_base(self : BrowserAdapter, base : String) -> String =
  #|(adapter, base) => adapter.normalizeBase(base)

///|
extern "js" fn signal_aborted(signal : @js_async.AbortSignal) -> Bool =
  #|signal => signal.aborted

///|
extern "js" fn BrowserAdapter::read(
  self : BrowserAdapter,
  base : String,
  relative : String,
  budget : Int,
  signal : @js_async.AbortSignal,
  task_signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, base, relative, budget, signal, taskSignal) => adapter.read(base, relative, budget, signal, taskSignal)

///|
extern "js" fn Reply::kind(self : Reply) -> String =
  #|reply => reply.kind

///|
extern "js" fn Reply::text(self : Reply) -> String =
  #|reply => reply.text

///|
extern "js" fn Reply::size(self : Reply) -> Int =
  #|reply => reply.size

///|
extern "js" fn Reply::status(self : Reply) -> Int =
  #|reply => reply.status
