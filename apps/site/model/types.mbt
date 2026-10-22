///|
pub(all) enum Section {
  Home
  Docs
  Articles
  /// The API pages below `/api/`.
  Api
} derive(Eq, Debug)

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with @debug.Debug::{to_repr}

///|
pub(all) struct ArticleSummary {
  route : String
  title : String
  date : String
  authors : Array[String]
  summary : String
} derive(Eq, Debug)

///|
pub extend ArticleSummary with Eq::{equal, not_equal}

///|
pub extend ArticleSummary with @debug.Debug::{to_repr}

///|
/// One line of the docs sidebar. An empty `route` is a label without a page.
pub(all) struct NavItem {
  route : String
  title : String
  depth : Int32
  /// The page has `status: proposed`; its link shows the "Proposed" badge.
  proposed : Bool
} derive(Eq, Debug)

///|
pub extend NavItem with Eq::{equal, not_equal}

///|
pub extend NavItem with @debug.Debug::{to_repr}

///|
/// One link of the "On this page" rail. `depth` is 0 for `h2` and 1 for `h3`.
pub(all) struct TocEntry {
  id : String
  text : String
  depth : Int32
} derive(Eq, Debug)

///|
pub extend TocEntry with Eq::{equal, not_equal}

///|
pub extend TocEntry with @debug.Debug::{to_repr}
