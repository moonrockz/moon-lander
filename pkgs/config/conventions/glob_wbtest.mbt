///|
/// Segment names for generated paths. Some hold characters that other glob
/// dialects read as pattern syntax, which this matcher reads literally.
let segment_names : Array[String] = [
  "src", "billing", "a?b", "[x]", "{a,b}", "pkg-1", "é", "a.b", "", "orders",
]

///|
/// A generated path: segment names, and a choice that a property uses to
/// split or change the path.
priv struct PathCase {
  choices : ReadOnlyArray[UInt32]
  pick : UInt32
} derive(Debug)

///|
impl @quickcheck.Arbitrary for PathCase with fn arbitrary(size, state) {
  let (choices, pick) : (ReadOnlyArray[UInt32], UInt32) = @quickcheck.Arbitrary::arbitrary(
    size, state,
  )
  { choices, pick }
}

///|
impl @shrink.Shrink for PathCase with fn shrink(self) {
  @shrink.Shrink::shrink((self.choices, self.pick)).map(parts => {
    let (choices, pick) = parts
    { choices, pick }
  })
}

///|
/// The path segments of the case. No segment is empty, because a path
/// segment always has a name.
fn PathCase::path(self : PathCase) -> Array[String] {
  self.choices
  .iter()
  .map(choice => {
    let name = segment_names[index_of(choice, segment_names.length())]
    if name.is_empty() {
      "x"
    } else {
      name
    }
  })
  .collect()
}

///|
/// A split position in `0..=length`.
fn PathCase::split(self : PathCase, length : Int) -> Int {
  index_of(self.pick, length + 1)
}

///|
/// `choice` as an index in `0..<count`.
fn index_of(choice : UInt, count : Int) -> Int {
  (choice % count.reinterpret_as_uint()).reinterpret_as_int()
}

///|
test "law: ** matches every segment list" {
  @expect.for_all(
    (input : PathCase) => {
      @expect.expect(segments_match(["**"], input.path())).to_equal(true)
    },
    count=200,
    max_size=12,
    max_shrinks=200,
    seed=6101,
  )
}

///|
test "law: a literal pattern matches only its own segments" {
  @expect.for_all(
    (input : PathCase) => {
      let path = input.path()
      let changed = path.copy()
      if !changed.is_empty() {
        let index = input.split(changed.length() - 1)
        changed[index] = changed[index] + "z"
      }
      @expect.expect_all(s => {
        s.expect(segments_match(path, path)).to_equal(true)
        s
        .expect(segments_match(path, [..path, "extra"]))
        .to_equal(false)
        if !path.is_empty() {
          s.expect(segments_match(path, changed)).to_equal(false)
          s.expect(segments_match(changed, path)).to_equal(false)
        }
      })
    },
    count=200,
    max_size=12,
    max_shrinks=200,
    seed=6102,
  )
}

///|
test "law: * matches one whole segment and never more" {
  @expect.for_all(
    (input : PathCase) => {
      let path = input.path()
      let stars = path.map(_ => "*")
      @expect.expect_all(s => {
        s.expect(segments_match(stars, path)).to_equal(true)
        s.expect(segments_match(stars, [..path, "extra"])).to_equal(false)
        if !path.is_empty() {
          s.expect(segments_match(stars, path[1:])).to_equal(false)
        }
      })
    },
    count=200,
    max_size=12,
    max_shrinks=200,
    seed=6103,
  )
}

///|
test "law: prefix/** matches the prefix and every path below it" {
  @expect.for_all(
    (input : PathCase) => {
      let path = input.path()
      let prefix = path[:input.split(path.length())].to_owned()
      @expect.expect_all(s => {
        s.expect(segments_match([..prefix, "**"], path)).to_equal(true)
        s.expect(segments_match([..prefix, "**"], prefix)).to_equal(true)
        s
        .expect(segments_match([..prefix, "*"], prefix))
        .to_equal(false)
      })
    },
    count=200,
    max_size=12,
    max_shrinks=200,
    seed=6104,
  )
}

///|
test "law: * in a segment matches any run of characters there" {
  @expect.for_all(
    (input : PathCase) => {
      let path = input.path()
      guard !path.is_empty() else { return }
      let name = path[input.split(path.length() - 1)]
      let chars : Array[Char] = name.iter().collect()
      let at = input.split(chars.length())
      let head = String::from_array(chars[:at])
      let tail = String::from_array(chars[at:])
      @expect.expect_all(s => {
        s.expect(segment_matches("\{head}*", name)).to_equal(true)
        s.expect(segment_matches("*\{tail}", name)).to_equal(true)
        s.expect(segment_matches("\{head}*\{tail}", name)).to_equal(true)
        s.expect(segment_matches("*", name)).to_equal(true)
        s.expect(segment_matches("\{name}?", name)).to_equal(false)
      })
    },
    count=200,
    max_size=12,
    max_shrinks=200,
    seed=6105,
  )
}

///|
test "Single-segment wildcard" {
  let pattern = entry_segments("packages/*")
  assert_eq(segments_match(pattern, ["packages", "billing"]), true)
  assert_eq(segments_match(pattern, ["packages", "billing", "core"]), false)
}

///|
test "Multi-segment wildcard" {
  let pattern = entry_segments("packages/**")
  assert_eq(segments_match(pattern, ["packages", "billing"]), true)
  assert_eq(segments_match(pattern, ["packages", "billing", "core"]), true)
  assert_eq(segments_match(entry_segments("packages/**/core"), ["packages", "core"]), true)
}

///|
test "other glob characters are literal" {
  assert_eq(segment_matches("a?c", "abc"), false)
  assert_eq(segment_matches("a?c", "a?c"), true)
  assert_eq(segment_matches("[ab]", "a"), false)
  assert_eq(segment_matches("{a,b}", "a"), false)
  assert_eq(segment_matches("a*c*e", "abcde"), true)
  assert_eq(segment_matches("*a", "*ba"), true)
}

///|
test "entries that leave the workspace are not confined" {
  assert_eq(is_confined("packages/*"), true)
  assert_eq(is_confined("packages/"), true)
  assert_eq(is_confined("."), true)
  assert_eq(is_confined(""), true)
  assert_eq(is_confined("../outside"), false)
  assert_eq(is_confined("packages/../../outside"), false)
  assert_eq(is_confined("/abs"), false)
  assert_eq(is_confined("C:/abs"), false)
  assert_eq(is_confined("C:rel"), false)
  assert_eq(is_confined("packages\\billing"), false)
  assert_eq(is_confined("..hidden"), true)
}

///|
test "the workspace root is never its own member" {
  assert_eq(is_member(wp("/w"), [], wp("/w")), false)
  assert_eq(is_member(wp("/w"), [], wp("/w/packages/a")), true)
  assert_eq(is_member(wp("/w"), ["packages/*"], wp("/w/packages/a")), false)
  assert_eq(is_member(wp("/w"), [], wp("/other/a")), false)
  assert_eq(is_member(wp("/"), [], wp("/a")), true)
}
