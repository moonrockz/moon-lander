///|
#external
priv type NodeFixture

///|
extern "js" fn NodeFixture::temp_dir(self : NodeFixture) -> String =
  #|fixture => fixture.tempDir()

///|
extern "js" fn NodeFixture::write(self : NodeFixture, path : String, text : String) -> Unit =
  #|(fixture, path, text) => fixture.write(path, text)

///|
extern "js" fn NodeFixture::remove_dir(self : NodeFixture, path : String) -> Unit =
  #|(fixture, path) => fixture.removeDir(path)

///|
extern "js" fn NodeFixture::mkdir(self : NodeFixture, path : String, permission~ : Int) -> Unit =
  #|(fixture, path, permission) => fixture.mkdir(path, permission)

///|
extern "js" fn NodeFixture::chmod(self : NodeFixture, path : String, permission : Int) -> Unit =
  #|(fixture, path, permission) => fixture.chmod(path, permission)

///|
fn temp_dir() -> String { node_fixture().temp_dir() }

///|
fn write(path : String, text : String) -> Unit { node_fixture().write(path, text) }

///|
fn remove_dir(path : String) -> Unit { node_fixture().remove_dir(path) }

///|
fn mkdir(path : String, permission~ : Int) -> Unit { node_fixture().mkdir(path, permission~) }

///|
fn chmod(path : String, permission : Int) -> Unit { node_fixture().chmod(path, permission) }

///|
extern "js" fn NodeFixture::symlink(self : NodeFixture, target : String, path : String) -> Unit =
  #|(fixture, target, path) => fixture.symlink(target, path)

///|
fn symlink(target~ : String, path : String) -> Unit { node_fixture().symlink(target, path) }

///|
#external
priv type NodeInspect

///|
extern "js" fn NodeFixture::faulty_stat(
  self : NodeFixture,
  locked : FixedArray[String],
  vanished : FixedArray[String],
  broken : FixedArray[String],
) -> NodeInspect =
  #|(fixture, locked, vanished, broken) => fixture.faultyStat(locked, vanished, broken)

///|
extern "js" fn NodeAdapter::answer_with(
  self : NodeAdapter,
  path : String,
  listing : Bool,
  inspect : NodeInspect,
) -> NodeReply =
  #|(adapter, path, listing, inspect) => adapter.answerWith(path, listing, inspect)

///|
/// The answer to `request`, with injected faults: a path in `locked` fails as a
/// file that another process holds open fails on Windows (`EBUSY`), a path in
/// `vanished` is gone when the adapter inspects it, and a path in `broken`
/// throws an error that is not a system error.
fn faulty_answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  locked~ : Array[String],
  vanished? : Array[String] = [],
  broken? : Array[String] = [],
) -> @config.FileTree raise {
  let inspect = node_fixture().faulty_stat(
    FixedArray::from_array(locked),
    FixedArray::from_array(vanished),
    FixedArray::from_array(broken),
  )
  answer_with(tree, request, running_platform(), (path, listing) => {
    node_files.answer_with(path, listing, inspect)
  })
}

///|
/// `load` with the injected faults of `faulty_answer`. On js the answer is
/// synchronous, and the async wrapper fits it to the type of `load_by`.
#warnings("-67")
async fn faulty_load(
  builder : @config.ConfigBuilder,
  locked~ : Array[String],
  vanished? : Array[String] = [],
) -> @config.Config raise {
  load_by(builder, async fn(tree, request, _) {
    faulty_answer(tree, request, locked~, vanished~)
  })
}

///|
/// Whether `error` is the error of the js adapter for a file call.
fn is_host_error(error : Error) -> Bool {
  error is NodeIoError(_)
}
