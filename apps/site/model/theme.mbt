///|
/// The theme after `theme` in the cycle `system`, `light`, `dark` of the theme control. A value that
/// is not a theme counts as `system`, so the next theme is `light`.
pub fn next_theme(theme : String) -> String {
  match theme {
    "light" => "dark"
    "dark" => "system"
    _ => "light"
  }
}
