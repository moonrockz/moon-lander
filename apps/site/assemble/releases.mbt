///|
/// One GitHub release, as the deploy reads it: the tag, its version, and the names of its assets.
struct Release {
  tag : String
  version : (Int, Int, Int)
  draft : Bool
  prerelease : Bool
  assets : Array[String]
} derive(Eq, Debug)

///|
/// The `jq` filter that `gh api --paginate` applies to each page of releases. It writes one release
/// on each line: the tag, the draft and prerelease flags, and the asset names joined with `,`, with
/// tabs between the fields. Each page gives its own lines, so no page limit drops a release.
let releases_filter : String = ".[] | [.tag_name, .draft, .prerelease, ([.assets[].name] | join(\",\"))] | @tsv"

///|
/// The value of the decimal digits `digits`.
fn number(digits : String) -> Int {
  let mut n = 0
  for c in digits {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  n
}

///|
/// The version of the tag `vX.Y.Z`, or `None` for any other tag.
fn tag_version(tag : String) -> (Int, Int, Int)? {
  guard tag.has_prefix("v") else { return None }
  let parts = tag[1:].split(".").collect()
  guard parts.length() == 3 else { return None }
  let numbers = []
  for part in parts {
    guard part != "" && part.iter().all(c => c >= '0' && c <= '9') else {
      return None
    }
    numbers.push(number(part.to_owned()))
  }
  Some((numbers[0], numbers[1], numbers[2]))
}

///|
/// The minor line `X.Y` of a version.
fn minor_of(version : (Int, Int, Int)) -> String {
  "\{version.0}.\{version.1}"
}

///|
/// The minor line `X.Y` as numbers, or `None` when `line` is not a minor line.
fn line_numbers(line : String) -> (Int, Int)? {
  guard @model.is_minor_line(line) else { return None }
  let parts = line.split(".").collect()
  Some((number(parts[0].to_owned()), number(parts[1].to_owned())))
}

///|
/// The releases in the output of `gh api --paginate` with `releases_filter`. A line whose tag is not
/// `vX.Y.Z` is left out, because it names no minor line.
fn parse_releases(text : String) -> Array[Release] {
  let found = []
  for line in text.split("\n") {
    let fields = line.split("\t").map(field => field.to_owned()).collect()
    guard fields.length() == 4 && tag_version(fields[0]) is Some(version) else {
      continue
    }
    found.push({
      tag: fields[0],
      version,
      draft: fields[1] == "true",
      prerelease: fields[2] == "true",
      assets: fields[3].split(",").map(name => name.to_owned()).filter(name => name != "").collect(),
    })
  }
  found
}

///|
/// The site asset of the minor line `line`.
fn asset_name(line : String) -> String {
  "site-\{line}.tar.gz"
}

///|
/// Compare two versions: negative, zero or positive.
fn compare_versions(a : (Int, Int, Int), b : (Int, Int, Int)) -> Int {
  if a.0 != b.0 {
    a.0 - b.0
  } else if a.1 != b.1 {
    a.1 - b.1
  } else {
    a.2 - b.2
  }
}

///|
/// The release that the deploy uses for each minor line, newest line first: the newest release of the
/// line by semantic version. Drafts, prereleases and lines below `since` are left out (design D22).
fn select_releases(releases : Array[Release], since : String) -> Array[Release] {
  let since = line_numbers(since).unwrap_or((0, 0))
  let newest : Map[String, Release] = Map([])
  for release in releases {
    let (major, minor, _) = release.version
    let below = major < since.0 || (major == since.0 && minor < since.1)
    if release.draft || release.prerelease || below {
      continue
    }
    let line = minor_of(release.version)
    match newest.get(line) {
      Some(kept) if compare_versions(kept.version, release.version) >= 0 => ()
      _ => newest.set(line, release)
    }
  }
  let selected = newest.values().collect()
  selected.sort_by((a, b) => compare_versions(b.version, a.version))
  selected
}

///|
/// A problem for each selected release that has no site asset. The problem names the release tag.
fn missing_assets(selected : Array[Release]) -> Array[@model.Problem] {
  selected.filter_map(release => {
    let name = asset_name(minor_of(release.version))
    if release.assets.contains(name) {
      None
    } else {
      Some(@model.problem(release.tag, "the release has no site asset `\{name}`"))
    }
  })
}

///|
/// The `versions.since` value of the text of `site/site.json`: the first minor line that ships site
/// assets.
fn versions_since(text : String) -> String raise @model.Invalid {
  let json = @json.parse(text) catch {
    error => raise @model.Invalid([@model.problem("site/site.json", "not valid JSON: \{error}")])
  }
  guard json is Object(fields) &&
    fields.get("versions") is Some(Object(versions)) &&
    versions.get("since") is Some(String(since)) &&
    @model.is_minor_line(since) else {
    raise @model.Invalid([
      @model.problem(
        "site/site.json",
        "`versions.since` must be a minor line, such as \"0.3\"",
      ),
    ])
  }
  since
}
