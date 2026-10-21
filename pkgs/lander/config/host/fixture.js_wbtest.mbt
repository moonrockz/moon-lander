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
