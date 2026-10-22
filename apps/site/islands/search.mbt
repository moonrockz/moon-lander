///|
priv enum Index {
  NotLoaded
  Loading
  Ready(Array[@model.SearchEntry])
  Failed
}

///|
/// The state of the search box.
priv struct SearchState {
  base : String
  mut index : Index
  mut query : String
  mut selected : Int
  mut found : Array[@model.SearchEntry]
}

///|
/// Loads `search-index.json` with the browser's `fetch` and `JSON.parse`, and passes each
/// entry as `[route, title, section, summary, text, ...headings]`. Entries with a field of
/// the wrong type are dropped, and other keys of an entry are ignored. The island does not use
/// `rabbita/http` or `@json`: together they would triple the size of `islands.js` (design D11).
extern "js" fn fetch_search_index(
  url : String,
  done : (Array[Array[String]]) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #| (url, done, failed) => {
  #|   const text = (v) => typeof v === "string";
  #|   fetch(url)
  #|     .then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
  #|     .then((items) => {
  #|       if (!Array.isArray(items)) throw new Error("not an array");
  #|       done(items
  #|         .filter((e) => e && ["route", "title", "section", "summary", "text"].every((k) => text(e[k]))
  #|           && Array.isArray(e.headings) && e.headings.every(text))
  #|         .map((e) => [e.route, e.title, e.section, e.summary, e.text, ...e.headings]));
  #|     })
  #|     .catch(() => failed());
  #| }

///|
/// Opens a page. `rabbita/nav` would do the same, but adds its runtime to `islands.js`.
extern "js" fn open_page(url : String) -> Unit = "(url) => location.assign(url)"

///|
/// Puts the search input and the empty result list in the mount element `id`. `on_input` gets the
/// text after each change. `on_key` gets each key press in the input and returns whether it used the
/// key, which then has no default action. A key press on a focused result link does not reach it, so
/// Enter on that link opens that link.
extern "js" fn mount_search(
  id : String,
  on_input : (String) -> Unit,
  on_key : (String) -> Bool,
) -> Unit =
  #| (id, onInput, onKey) => {
  #|   const mount = document.getElementById(id);
  #|   const box = document.createElement("div");
  #|   box.className = "search";
  #|   const input = document.createElement("input");
  #|   input.id = "search-input";
  #|   input.type = "search";
  #|   input.placeholder = "Search (/)";
  #|   input.setAttribute("aria-label", "Search the site");
  #|   const list = document.createElement("ul");
  #|   list.className = "search-results";
  #|   list.hidden = true;
  #|   input.addEventListener("input", () => onInput(input.value));
  #|   input.addEventListener("keydown", (e) => { if (onKey(e.key)) e.preventDefault(); });
  #|   box.append(input, list);
  #|   mount.replaceChildren(box);
  #| }

///|
/// Sets the text of the search input.
extern "js" fn set_query(text : String) -> Unit =
  #| (text) => { const input = document.getElementById("search-input"); if (input) input.value = text; }

///|
/// Shows the results in the result list. Each result is a plain link, so it navigates without a
/// router. `empty` shows "No results"; `hidden` hides the list.
extern "js" fn show_results(
  urls : FixedArray[String],
  titles : FixedArray[String],
  sections : FixedArray[String],
  selected : Int,
  empty : Bool,
  hidden : Bool,
) -> Unit =
  #| (urls, titles, sections, selected, empty, hidden) => {
  #|   const list = document.querySelector("#site-search .search-results");
  #|   if (!list) return;
  #|   list.hidden = hidden;
  #|   const items = urls.map((url, i) => {
  #|     const li = document.createElement("li");
  #|     if (i === selected) li.className = "selected";
  #|     const a = document.createElement("a");
  #|     a.href = url;
  #|     const title = document.createElement("span");
  #|     title.textContent = titles[i];
  #|     const section = document.createElement("small");
  #|     section.textContent = sections[i];
  #|     a.append(title, section);
  #|     li.append(a);
  #|     return li;
  #|   });
  #|   if (empty) {
  #|     const li = document.createElement("li");
  #|     li.className = "search-empty";
  #|     li.textContent = "No results";
  #|     items.push(li);
  #|   }
  #|   list.replaceChildren(...items);
  #| }

///|
/// Shows the results of the current query.
fn render(state : SearchState) -> Unit {
  state.found = match state.index {
    Ready(entries) => @model.search(entries, state.query)
    _ => []
  }
  let blank = state.query.trim() == ""
  show_results(
    FixedArray::from_array(state.found.map(e => @model.result_url(state.base, e))),
    FixedArray::from_array(state.found.map(e => e.title)),
    FixedArray::from_array(state.found.map(e => e.section)),
    state.selected,
    !blank && state.found.is_empty() && state.index is (Ready(_) | Failed),
    blank,
  )
}

///|
/// The search box in the mount element `id`. It loads the index on the first key press, and opens a
/// result on a click or on Enter. Without JavaScript the mount stays empty.
fn search_box(id : String, base : String) -> Unit {
  let state : SearchState = {
    base,
    index: NotLoaded,
    query: "",
    selected: 0,
    found: [],
  }
  mount_search(
    id,
    query => {
      state.query = query
      state.selected = 0
      if state.index is NotLoaded {
        state.index = Loading
        fetch_search_index(
          @model.search_index_url(base),
          rows => {
            state.index = Ready(rows.filter_map(@model.SearchEntry::from_fields))
            render(state)
          },
          () => {
            state.index = Failed
            render(state)
          },
        )
      }
      render(state)
    },
    key => {
      match key {
        "ArrowDown" | "ArrowUp" => {
          state.selected = @model.move_selection(
            state.selected,
            state.found.length(),
            key,
          )
          render(state)
          true
        }
        "Enter" if state.found.length() > 0 => {
          open_page(@model.result_url(base, state.found[state.selected]))
          true
        }
        "Escape" => {
          state.query = ""
          state.selected = 0
          set_query("")
          render(state)
          true
        }
        _ => false
      }
    },
  )
}
