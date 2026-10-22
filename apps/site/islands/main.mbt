///|
extern "js" fn element_exists(id : String) -> Bool =
  #| (id) => document.getElementById(id) !== null

///|
/// The base path of the site from `data-base` on `<html>` (design D5), so the islands build links
/// with the base path and need no build-time constant.
extern "js" fn base_path() -> String =
  #| () => document.documentElement.dataset.base ?? "/"

///|
/// Sets `data-js` on `<html>`. The stylesheet hides the main links behind the menu button only when
/// it is set, so a page without JavaScript keeps its links.
extern "js" fn mark_js() -> Unit =
  #| () => { document.documentElement.dataset.js = "true" }

///|
extern "js" fn focus_search_on_slash() -> Unit =
  #| () => document.addEventListener("keydown", (e) => {
  #|   const t = document.activeElement?.tagName;
  #|   if (e.key === "/" && t !== "INPUT" && t !== "TEXTAREA") {
  #|     e.preventDefault(); document.getElementById("search-input")?.focus();
  #|   }
  #| })

///|
/// The client islands. Each one fills its empty mount element, so a page without JavaScript keeps
/// its full content. The theme control and the menu button are Rabbita islands. The search box uses
/// plain DOM calls: the Rabbita command runtime that it would need puts `islands.js` above the size
/// budget of design D13.
fn main {
  mark_js()
  let base = base_path()
  if element_exists("site-search") {
    search_box("site-search", base)
    focus_search_on_slash()
  }
  if element_exists("site-version") {
    version_switcher("site-version", base)
  }
  if element_exists("site-theme") {
    @rabbita.new(theme_toggle).mount("site-theme")
  }
  if element_exists("site-nav") {
    @rabbita.new(menu_toggle).mount("site-nav")
  }
  add_copy_buttons(".prose pre")
  if element_exists("site-toc") {
    track_toc("site-toc")
  }
}
