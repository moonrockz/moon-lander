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
extern "js" fn BrowserAdapter::supported(self : BrowserAdapter, backend : String) -> Bool =
  #|(adapter, backend) => adapter.supported(backend)

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
extern "js" fn BrowserAdapter::read_file(
  self : BrowserAdapter,
  file : File,
  budget : Int,
  signal : @js_async.AbortSignal,
  task_signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, file, budget, signal, taskSignal) => adapter.readFile(file, budget, signal, taskSignal)

///|
extern "js" fn BrowserAdapter::list_directory(
  self : BrowserAdapter,
  handle : DirectoryHandle,
  relative : String,
  signal : @js_async.AbortSignal,
  task_signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, handle, relative, signal, taskSignal) => adapter.listDirectory(handle, relative, signal, taskSignal)

///|
extern "js" fn BrowserAdapter::read_directory_file(
  self : BrowserAdapter,
  handle : DirectoryHandle,
  relative : String,
  budget : Int,
  signal : @js_async.AbortSignal,
  task_signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, handle, relative, budget, signal, taskSignal) => adapter.readDirectoryFile(handle, relative, budget, signal, taskSignal)

///|
extern "js" fn Reply::count(self : Reply) -> Int =
  #|reply => reply.names ? reply.names.length : 0

///|
extern "js" fn Reply::name_at(self : Reply, index : Int) -> String =
  #|(reply, index) => reply.names[index]

///|
extern "js" fn Reply::directory_at(self : Reply, index : Int) -> Bool =
  #|(reply, index) => reply.directories[index]

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
