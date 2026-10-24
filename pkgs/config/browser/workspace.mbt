///|
/// Confine convention discovery to one mounted workspace. Remove the system
/// directory, the global user directory and the application home, and stop the
/// walk-up at the mount root. Project, environment, local and user override
/// files inside the mount keep their normal behavior. This does not set isolated
/// mode. A caller can set a narrower boundary later; `load` still rejects any
/// request outside its mounts.
pub fn workspace(
  conventions : @conventions.Conventions,
  mount : Mount,
) -> @conventions.Conventions {
  conventions
  |> @conventions.without(SystemDir)
  |> @conventions.without(UserConfigDir)
  |> @conventions.without(AppHome)
  |> @conventions.boundary(mount.root)
}
