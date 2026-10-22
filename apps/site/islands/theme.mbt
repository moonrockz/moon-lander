///|
/// The stored theme, or `system` when there is none or the browser blocks storage.
extern "js" fn stored_theme() -> String =
  #| () => {
  #|   try { const t = localStorage.getItem("site-theme"); return t === "light" || t === "dark" ? t : "system" }
  #|   catch (e) { return "system" }
  #| }

///|
/// Stores `theme` and applies it. The `system` theme removes `data-theme`, so the stylesheet follows
/// the color scheme of the operating system.
extern "js" fn apply_theme(theme : String) -> Unit =
  #| (theme) => {
  #|   try { localStorage.setItem("site-theme", theme) } catch (e) {}
  #|   if (theme === "system") delete document.documentElement.dataset.theme;
  #|   else document.documentElement.dataset.theme = theme;
  #| }

///|
/// The theme control. Each click selects the next theme of `@model.next_theme`.
fn theme_toggle() -> @rabbita.Val[@html.Html] {
  let (theme, emit) = @rabbita.create_state(stored_theme(), update=(
    theme,
    _msg : Unit,
    _,
  ) => {
    let next = @model.next_theme(theme)
    (next, @rabbita.effect(fn() noraise { apply_theme(next) }))
  })
  theme.view(t => {
    @html.button(
      class="theme-toggle icon-button",
      type_="button",
      title="Theme: \{t}",
      on_click=emit(()),
      attrs=@html.Attrs::build().aria_label("Theme: \{t}"),
      @html.span(
        class="theme-icon theme-\{t}",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      ),
    )
  })
}
