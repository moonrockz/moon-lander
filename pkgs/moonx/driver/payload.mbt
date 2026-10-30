///|
/// A directory acquired exclusively by this driver. No caller path can make
/// this value. Creation and registration happen in the same protected region.
priv struct OwnedPayload {
  root : String
  mut removed : Bool
}

///|
async fn materialize(
  node : @moonx.NodeLaunch,
  owner : Ref[OwnedPayload?],
) -> @moonx.Command {
  let owned = @runtime.protect_from_cancel(() => {
    let root = @fs.tmpdir(prefix="moon-lander-moonx")
    let owned = { root, removed: false }
    owner.val = Some(owned)
    owned
  })
  let directories : Map[String, Bool] = Map([])
  for entry in node.payload().files() {
    let path = entry.path().to_string()
    let segments = path.split("/").to_array()
    for end in 1..<segments.length() {
      let prefix = segments[:end].join("/")
      if !directories.contains(prefix) {
        @fs.mkdir(owned.root + "/" + prefix, permission=0o700)
        directories.set(prefix, true)
      }
    }
    let file = @runtime.protect_from_cancel(() => @fs.open(
      owned.root + "/" + path, mode=WriteOnly, create_mode=CreateNew,
      permission=0o600,
    ))
    defer file.close()
    @io.Writer::write(file, entry.bytes())
  }
  // The absolute entry avoids cwd changes and relative executable resolution.
  let root = @fs.realpath(owned.root)
  let prefix = @moonx.Arguments::parse([root + "/" + node.payload().entry().to_string()])
  @moonx.Command::new(node.executable(), prefix.concat(node.arguments()))
}

///|
async fn OwnedPayload::cleanup(self : OwnedPayload) -> Unit {
  if self.removed { return }
  // Check the root itself without following links as well as relying on the
  // frozen recursive remover's no-follow directory entries. The owned child
  // has already been reaped before this method is called.
  let kind = @fs.kind(self.root, follow_symlink=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => {
      self.removed = true
      return
    }
    error => raise error
  }
  match kind {
    Directory => @fs.rmdir(self.root, recursive=true)
    _ => @fs.remove(self.root)
  }
  self.removed = true
}
