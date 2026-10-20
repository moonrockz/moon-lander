///|
/// The output file of a route, relative to the output directory. A route is a directory that starts
/// and ends with `/`, so the host serves `/x/` from `x/index.html` without a rewrite rule.
pub fn route_file(route : String) -> String {
  route[1:].to_owned() + "index.html"
}
