///|
#external
priv type NodeAdapter

///|
#external
priv type NodeReply

///|
priv suberror NodeIoError {
  NodeIoError(String)
}

///|
extern "js" fn NodeAdapter::answer(
  self : NodeAdapter,
  path : String,
  listing : Bool,
) -> NodeReply =
  #|(adapter, path, listing) => adapter.answer(path, listing)

///|
extern "js" fn NodeReply::kind(self : NodeReply) -> String =
  #|reply => reply.kind

///|
extern "js" fn NodeReply::text(self : NodeReply) -> String =
  #|reply => reply.text

///|
extern "js" fn NodeReply::error(self : NodeReply) -> String =
  #|reply => reply.error

///|
extern "js" fn NodeReply::names(self : NodeReply) -> FixedArray[String] =
  #|reply => reply.names

///|
extern "js" fn NodeReply::kinds(self : NodeReply) -> FixedArray[String] =
  #|reply => reply.kinds

///|
fn answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  platform : @config.Platform,
) -> @config.FileTree raise {
  let (path, listing) = match request {
    ReadFile(path) => (path, false)
    ListDir(path) => (path, true)
  }
  let reply = node_files.answer(from_slash(path, platform), listing)
  match reply.kind() {
    "missing" => tree.with_missing(path)
    "file" => tree.with_file(path, reply.text())
    "directory" => {
      let names = reply.names()
      let kinds = reply.kinds()
      let entries : Array[@config.DirEntry] = []
      for i, name in names {
        let kind : @config.EntryKind = match kinds[i] {
          "file" => File
          "directory" => Directory
          _ => Other
        }
        entries.push({ name, kind })
      }
      tree.with_listing(path, entries)
    }
    _ => raise NodeIoError(reply.error())
  }
}

///|
extern "js" fn node_platform() -> String =
  #|() => process.platform

///|
fn running_platform() -> @config.Platform {
  match node_platform() {
    "win32" => Windows
    "darwin" => MacOs
    _ => Linux
  }
}

///|
let node_files : NodeAdapter = node_adapter()
