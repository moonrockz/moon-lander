///|
/// The parsed path of `text`, or a test failure.
fn path(text : String) -> @config.FileTreePath raise {
  @config.FileTreePath::parse(text)
}

///|
/// The rule that `text` breaks, or `None` when it parses.
fn broken_rule(text : String) -> @config.FilePathRule? {
  try @config.FileTreePath::parse(text) catch {
    InvalidFilePath(rule~, text=input) => {
      // The error names the input as given.
      guard input == text else { abort("the error does not name the input") }
      Some(rule)
    }
    _ => abort("expected an invalid-path error")
  } noraise {
    _ => None
  }
}

///|
test "Invalid portable input" {
  @expect.expect(broken_rule("")).to_equal(Some(Empty))
  @expect.expect(broken_rule("/w/a\u{0}b")).to_equal(Some(Nul))
  @expect.expect(broken_rule("C:\\w\\acme.toml")).to_equal(Some(Backslash))
  @expect.expect(broken_rule("w\\acme.toml")).to_equal(Some(Backslash))
  // One side of each limit parses.
  @expect.expect(broken_rule("a")).to_equal(None)
  @expect.expect(broken_rule("/w/a b")).to_equal(None)
  @expect.expect(broken_rule("/w/a/b")).to_equal(None)
}

///|
test "Drive-relative paths are rejected" {
  @expect.expect(broken_rule("C:")).to_equal(Some(DriveRelative))
  @expect.expect(broken_rule("C:acme.toml")).to_equal(Some(DriveRelative))
  @expect.expect(broken_rule("z:w")).to_equal(Some(DriveRelative))
  @expect.expect(broken_rule("C:/")).to_equal(None)
  @expect.expect(broken_rule("z:/w")).to_equal(None)
  // Not a drive: the first character is not an ASCII letter, or `:` is later.
  @expect.expect(broken_rule("1:w")).to_equal(None)
  @expect.expect(broken_rule("ab:w")).to_equal(None)
}

///|
test "Incomplete UNC root is rejected" {
  @expect.expect(broken_rule("//")).to_equal(Some(IncompleteUnc))
  @expect.expect(broken_rule("//server")).to_equal(Some(IncompleteUnc))
  @expect.expect(broken_rule("//server/")).to_equal(Some(IncompleteUnc))
  @expect.expect(broken_rule("///share")).to_equal(Some(IncompleteUnc))
  @expect.expect(broken_rule("//server/share")).to_equal(None)
  @expect.expect(broken_rule("//server/share/a")).to_equal(None)
}

///|
test "the error message names the input and the rule" {
  try @config.FileTreePath::parse("C:w") catch {
    error =>
      @expect.expect(error.message()).to_equal(
        "Invalid file path \"C:w\": a drive letter and : must have / after them, for example C:/",
      )
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "Windows drive root remains absolute" {
  let file = path("C:/acme.toml")
  guard file.parent() is Some(root) else { fail("C:/acme.toml has a parent") }
  @expect.expect(root.to_string()).to_equal("C:/")
  @expect.expect(root.is_root()).to_equal(true)
  @expect.expect(root.parent()).to_equal(None)
  @expect.expect(file.is_absolute()).to_equal(true)
}

///|
test "UNC share is a root" {
  let file = path("//server/share/acme.toml")
  guard file.parent() is Some(share) else { fail("the file has a parent") }
  @expect.expect(share.to_string()).to_equal("//server/share")
  @expect.expect(share).to_equal(path("//server/share"))
  @expect.expect(share.parent()).to_equal(None)
  @expect.expect(file.root()).to_equal(share)
}

///|
test "POSIX and current-directory roots" {
  @expect.expect(path("/").parent()).to_equal(None)
  @expect.expect(path(".").parent()).to_equal(None)
  @expect.expect(path(".").is_absolute()).to_equal(false)
  let file = path("acme.toml")
  @expect.expect(file.parent()).to_equal(Some(path(".")))
  @expect.expect(file.to_string()).to_equal("acme.toml")
  @expect.expect(file.is_absolute()).to_equal(false)
}

///|
test "a path keeps case and drops empty and dot names, and keeps parent names" {
  @expect.expect(path("/W//Acme/./b/").to_string()).to_equal("/W/Acme/b")
  @expect.expect(path("./a").to_string()).to_equal("a")
  @expect.expect(path("c:/w") == path("C:/w")).to_equal(false)
  // A `..` name is not applied: through a symbolic link it is not the lexical
  // parent.
  @expect.expect(path("/w/link/../a").names()).to_equal(["w", "link", "..", "a"])
  @expect.expect(path("/w/link/../a") == path("/w/a")).to_equal(false)
}

///|
test "Child below a drive root" {
  let root = path("D:/")
  let file = root.join("acme.toml")
  @expect.expect(file.to_string()).to_equal("D:/acme.toml")
  @expect.expect(file.parent()).to_equal(Some(root))
  @expect.expect(file.name()).to_equal(Some("acme.toml"))
  @expect.expect(root.child("acme.toml")).to_equal(file)
}

///|
test "a join gives an absolute text its own path and parses the text one time" {
  @expect.expect(path("/w").join("/x/a")).to_equal(path("/x/a"))
  @expect.expect(path("/w").join("C:/a")).to_equal(path("C:/a"))
  @expect.expect(path("C:/w").join("sub/a.toml").to_string()).to_equal(
    "C:/w/sub/a.toml",
  )
  @expect.expect(path("//s/sh").join("a").to_string()).to_equal("//s/sh/a")
  let dir = path("/w")
  try dir.join("a\\b") catch {
    InvalidFilePath(rule~, ..) => @expect.expect(rule).to_equal(Backslash)
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("expected an invalid-path error")
  }
}

///|
test "a child name is one name" {
  let dir = path("/w")
  for name in ["", ".", "..", "a/b"] {
    try dir.child(name) catch {
      InvalidFilePath(rule~, ..) => @expect.expect(rule).to_equal(NotAName)
      _ => fail("expected an invalid-path error")
    } noraise {
      _ => fail("\{name} is not one name")
    }
  }
  @expect.expect(dir.child(".acme").to_string()).to_equal("/w/.acme")
  @expect.expect(dir.child("a b").to_string()).to_equal("/w/a b")
}

///|
test "containment is name by name and needs the same root" {
  let config = path("/w/config")
  @expect.expect(path("/w/config/acme.toml").is_within(config)).to_equal(true)
  @expect.expect(config.is_within(config)).to_equal(true)
  @expect.expect(path("/w/config2/acme.toml").is_within(config)).to_equal(false)
  @expect.expect(path("/w").is_within(config)).to_equal(false)
  @expect.expect(path("C:/w").is_within(path("/"))).to_equal(false)
  @expect.expect(path("//s/sh/a").is_within(path("//s/sh"))).to_equal(true)
}

///|
test "the common directory of paths" {
  @expect.expect(
    @config.FileTreePath::common_dir([path("/w/a.toml"), path("/w/.config/a.toml")]),
  ).to_equal(Some(path("/w")))
  @expect.expect(
    @config.FileTreePath::common_dir([path("C:/a.toml"), path("C:/.config/a.toml")]),
  ).to_equal(Some(path("C:/")))
  @expect.expect(
    @config.FileTreePath::common_dir([path("C:/a.toml"), path("D:/a.toml")]),
  ).to_equal(None)
  @expect.expect(@config.FileTreePath::common_dir([])).to_equal(None)
}

///|
test "Native Windows source path" {
  @expect.expect(
    @config.FileTreePath::from_native("C:\\cfg\\app.toml", Windows).to_string(),
  ).to_equal("C:/cfg/app.toml")
  @expect.expect(
    @config.FileTreePath::from_native("C:/cfg/app.toml", Windows),
  ).to_equal(path("C:/cfg/app.toml"))
  // A Linux file name can hold `\`, so only Windows converts it.
  try @config.FileTreePath::from_native("/w/a\\b", Linux) catch {
    InvalidFilePath(rule~, ..) => @expect.expect(rule).to_equal(Backslash)
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("Linux does not convert \\")
  }
}

///|
test "Native UNC source path" {
  let share = @config.FileTreePath::from_native(
    "\\\\server\\share\\acme.toml",
    Windows,
  )
  @expect.expect(share.to_string()).to_equal("//server/share/acme.toml")
  @expect.expect(share.root().to_string()).to_equal("//server/share")
  @expect.expect(share.to_native(Windows)).to_equal(
    "\\\\server\\share\\acme.toml",
  )
}

///|
test "native conversion keeps a drive-relative path an error" {
  try @config.FileTreePath::from_native("C:w\\acme.toml", Windows) catch {
    InvalidFilePath(text~, rule~) => {
      @expect.expect(rule).to_equal(DriveRelative)
      @expect.expect(text).to_equal("C:w\\acme.toml")
    }
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("C:w is relative to the current directory of drive C")
  }
}

///|
test "native text for a file call" {
  @expect.expect(path("C:/").to_native(Windows)).to_equal("C:\\")
  @expect.expect(path("C:/w/a.toml").to_native(Windows)).to_equal(
    "C:\\w\\a.toml",
  )
  @expect.expect(path("/w/a.toml").to_native(Linux)).to_equal("/w/a.toml")
  @expect.expect(path("/").to_native(MacOs)).to_equal("/")
}

///|
test "paths are map keys and sort by their text" {
  let map : Map[@config.FileTreePath, Int] = Map([])
  map[path("/w/a")] = 1
  @expect.expect(map.get(path("/w//a/"))).to_equal(Some(1))
  let sorted = [path("/w/b"), path("/w/a")]
  sorted.sort()
  @expect.expect(sorted).to_equal([path("/w/a"), path("/w/b")])
}

///|
test "Relative source uses its explicit base" {
  // No process state: the builder gives the working directory and the platform.
  let builder = @config.builder()
    |> @config.working_dir("C:/w")
    |> @config.platform(Windows)
    |> @config.file("acme.toml")
    |> @config.format(@toml.format())
  guard @config.load(builder, @config.FileTree::new()) is Need(requests) else {
    fail("the tree does not hold the file")
  }
  @expect.expect(requests).to_equal([ReadFile(path("C:/w/acme.toml"))])
}

///|
test "a native Windows source does not join the working directory" {
  let builder = @config.builder()
    |> @config.working_dir("C:/proj")
    |> @config.platform(Windows)
    |> @config.file("C:\\cfg\\app.toml")
    |> @config.format(@toml.format())
  guard @config.load(builder, @config.FileTree::new()) is Need(requests) else {
    fail("the tree does not hold the file")
  }
  @expect.expect(requests).to_equal([ReadFile(path("C:/cfg/app.toml"))])
}

///|
test "an invalid working directory is a configuration error" {
  let builder = @config.builder() |> @config.working_dir("C:proj")
  try @config.load(builder, @config.FileTree::new()) catch {
    InvalidFilePath(text~, rule~) => {
      @expect.expect(text).to_equal("C:proj")
      @expect.expect(rule).to_equal(DriveRelative)
    }
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("expected an invalid-path error")
  }
}

///|
test "Absence respects path segments" {
  let tree = @config.FileTree::new().with_missing(path("/w/config"))
  @expect.expect(tree.file(path("/w/config/acme.toml"))).to_equal(Missing)
  @expect.expect(tree.file(path("/w/config2/acme.toml"))).to_equal(Unknown)
}

///|
test "tracer: a parsed path reaches a typed request, the tree answer and one value" {
  let cases : Array[(String, @config.Platform, String)] = [
    ("/w", Linux, "/w/acme.toml"),
    ("C:\\w", Windows, "C:/w/acme.toml"),
  ]
  for case in cases {
    let (dir, platform, expected) = case
    let builder = @config.builder()
      |> @config.working_dir(dir)
      |> @config.platform(platform)
      |> @config.format(@toml.format())
      |> @config.file("acme.toml")
    let file = path(expected)
    guard @config.load(builder, @config.FileTree::new()) is Need(requests) else {
      fail("the tree does not hold the file")
    }
    @expect.expect(requests).to_equal([ReadFile(file)])
    let tree = @config.FileTree::new().with_file(file, "name = \"tracer\"")
    guard @config.load(builder, tree) is Done(config) else {
      fail("the tree holds the file")
    }
    @expect.expect(@config.get_text(config, "name")).to_equal("tracer")
    @expect.expect(config.reports()[0].path).to_equal(Some(expected))
  }
}

///|
/// The parsed path of the test path `text`.
fn p(text : String) -> @config.FileTreePath {
  @config.FileTreePath::parse(text) catch {
    _ => abort("invalid test path \{text}")
  }
}

///|
/// The requests of a load step that needs files.
fn[T] needs(step : @config.LoadStep[T]) -> Array[@config.FileRequest] {
  guard step is Need(requests) else { abort("the load step needs no files") }
  requests
}

///|
test "a host absolute path converts with the path rules" {
  let host = @lander_core.AbsolutePath::parse("C:\\w\\app.toml")
  @expect.expect(@config.FileTreePath::from_absolute(host)).to_equal(
    p("C:/w/app.toml"),
  )
  let unc = @lander_core.AbsolutePath::parse("\\\\server\\share\\a")
  @expect.expect(@config.FileTreePath::from_absolute(unc).to_string()).to_equal(
    "//server/share/a",
  )
  // `AbsolutePath` keeps `\` in a POSIX path; the file-tree path rejects it.
  let posix = @lander_core.AbsolutePath::parse("/w/a\\b")
  try @config.FileTreePath::from_absolute(posix) catch {
    InvalidFilePath(rule~, ..) => @expect.expect(rule).to_equal(Backslash)
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("expected an invalid-path error")
  }
}
