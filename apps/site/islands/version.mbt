///|
/// The site root from `data-site-root` on `<html>` (design D22), or `base` when the page has none.
extern "js" fn site_root_of(base : String) -> String =
  #| (base) => document.documentElement.dataset.siteRoot ?? base

///|
/// Loads `versions.json` with the browser's `fetch`, and passes the latest line (empty before the
/// first release), whether `next` exists, and the kept lines. A site without the file, such as a
/// local build, gets no call, so the switcher stays empty.
extern "js" fn fetch_versions(
  url : String,
  done : (String, Bool, Array[String]) -> Unit,
) -> Unit =
  #| (url, done) => {
  #|   fetch(url)
  #|     .then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
  #|     .then((v) => {
  #|       const lines = Array.isArray(v.versions) ? v.versions.filter((l) => typeof l === "string") : [];
  #|       done(typeof v.latest === "string" ? v.latest : "", v.next === true, lines);
  #|     })
  #|     .catch(() => {});
  #| }

///|
/// Asks the host for `url` with a `HEAD` request and passes whether the page exists.
extern "js" fn page_exists(url : String, done : (Bool) -> Unit) -> Unit =
  #| (url, done) => { fetch(url, { method: "HEAD" }).then((r) => done(r.ok)).catch(() => done(false)) }

///|
/// The current path of the page.
extern "js" fn current_path() -> String = "() => location.pathname"

///|
/// Puts a labelled version list in the mount element `id`, with `selected` chosen. `on_change` gets
/// the value of each new choice.
extern "js" fn mount_versions(
  id : String,
  values : FixedArray[String],
  labels : FixedArray[String],
  selected : String,
  on_change : (String) -> Unit,
) -> Unit =
  #| (id, values, labels, selected, onChange) => {
  #|   const mount = document.getElementById(id);
  #|   const list = document.createElement("select");
  #|   list.className = "version-select";
  #|   list.setAttribute("aria-label", "Docs version");
  #|   values.forEach((v, i) => {
  #|     const o = document.createElement("option");
  #|     o.value = v; o.textContent = labels[i]; o.selected = v === selected;
  #|     list.appendChild(o);
  #|   });
  #|   list.addEventListener("change", () => onChange(list.value));
  #|   mount.replaceChildren(list);
  #| }

///|
/// The version switcher (design D22). It lists the choices of `versions.json` at the site root. On a
/// choice it opens the same page in the target version when the host has it, or else the root of the
/// target version.
fn version_switcher(id : String, base : String) -> Unit {
  let root = site_root_of(base)
  fetch_versions(root + "versions.json", (latest, next, versions) => {
    let latest = if latest == "" { None } else { Some(latest) }
    let file : @model.VersionsFile = { latest, next, versions }
    let choices = file.choices()
    let current = @model.current_choice(root, base, latest)
    mount_versions(
      id,
      FixedArray::from_array(choices),
      FixedArray::from_array(choices.map(choice => @model.choice_label(choice, latest))),
      current,
      choice => {
        let target = @model.choice_base(root, choice)
        let path = current_path()
        page_exists(@model.switch_probe(path, base, target), exists => {
          open_page(@model.switch_url(path, base, target, exists))
        })
      },
    )
  })
}
