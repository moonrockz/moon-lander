///|
/// An owned resolved target: the owning resource's retrieval URI (None for
/// an unnamed input document), the pointer within it, and the immutable value
/// found there.
pub struct Location {
  resource : UriReference?
  pointer : JsonPointer
  target : @json.Value
} derive(Debug)

///|
pub extend Location with @debug.Debug::{to_repr}

///|
pub fn Location::resource(self : Location) -> UriReference? {
  self.resource
}

///|
pub fn Location::pointer(self : Location) -> JsonPointer {
  self.pointer
}

///|
pub fn Location::target(self : Location) -> @json.Value {
  self.target
}

///|
/// Normalized resource identity plus pointer; equal for every access path.
pub fn Location::identity(self : Location) -> String {
  let resource = match self.resource {
    Some(uri) => uri.identity()
    None => ""
  }
  resource + "#" + self.pointer.to_string()
}

///|
/// One reference in a chain: where it appeared (None for the initial input),
/// its source text, and its absolute form when a base was available.
pub struct ReferenceStep {
  site : Location?
  reference : Reference
  resolved : UriReference?
} derive(Debug)

///|
pub extend ReferenceStep with @debug.Debug::{to_repr}

///|
pub fn ReferenceStep::site(self : ReferenceStep) -> Location? {
  self.site
}

///|
pub fn ReferenceStep::reference(self : ReferenceStep) -> Reference {
  self.reference
}

///|
pub fn ReferenceStep::resolved(self : ReferenceStep) -> UriReference? {
  self.resolved
}

///|
/// A resolution result. `complete` is false when the answer depends on input
/// that was not supplied or on work beyond the limits; a broken pointer or a
/// cycle is a complete failure.
pub struct Resolution {
  target : Location?
  priv chain : Array[ReferenceStep]
  priv diagnostics : Array[@json.Diagnostic]
  complete : Bool
} derive(Debug)

///|
pub extend Resolution with @debug.Debug::{to_repr}

///|
pub fn Resolution::target(self : Resolution) -> Location? {
  self.target
}

///|
pub fn Resolution::chain(self : Resolution) -> Array[ReferenceStep] {
  self.chain.copy()
}

///|
pub fn Resolution::diagnostics(self : Resolution) -> Array[@json.Diagnostic] {
  self.diagnostics.copy()
}

///|
pub fn Resolution::complete(self : Resolution) -> Bool {
  self.complete
}

///|
priv enum Hop {
  Found(Location)
  Failed(@json.Diagnostic, Bool)
}

///|
fn ResourceSet::hop(
  self : ResourceSet,
  reference : Reference,
  base : UriReference?,
  chain : Array[ReferenceStep],
  site : Location?,
  limits : @json.Limits,
) -> Hop {
  let absolute = if reference.uri.is_absolute() {
    Ok(reference.uri)
  } else {
    match base {
      Some(base) if base.is_absolute() => reference.uri.resolve(base, limits~)
      _ => {
        chain.push({ site, reference, resolved: None, })
        return Failed(
          @json.Diagnostic::new(
            @json.MissingBaseUri,
            "Relative reference " +
            reference.text() +
            " has no absolute base URI",
          ),
          false,
        )
      }
    }
  }
  let absolute = match absolute {
    Ok(uri) => uri
    Err(d) => {
      chain.push({ site, reference, resolved: None, })
      return Failed(d, d.code() != @json.LimitExceeded)
    }
  }
  chain.push({ site, reference, resolved: Some(absolute), })
  let resource = match self.get(absolute) {
    Some(resource) => resource
    None =>
      return Failed(
        @json.Diagnostic::new(
          @json.UnavailableResource,
          "Resource " + absolute.without_fragment().text() + " was not supplied",
        ),
        false,
      )
  }
  let pointer = match reference.fragment {
    WholeResource => JsonPointer::{ parts: [], }
    PointerFragment(pointer) => pointer
    IdentifierFragment(name) =>
      return Failed(
        @json.Diagnostic::new(
          @json.UnsupportedCheck,
          "Identifier fragment #" + name + " requires a schema scope index",
        ),
        false,
      )
  }
  match pointer.resolve(resource.value, limits~) {
    Ok(target) => Found({ resource: Some(resource.uri), pointer, target, })
    Err(d) => Failed(d, d.code() != @json.LimitExceeded)
  }
}

///|
/// Resolve one reference against the explicit resources. A relative reference
/// uses `base`, else the set's root base. Nothing is fetched or executed.
pub fn ResourceSet::resolve(
  self : ResourceSet,
  reference : Reference,
  base~ : UriReference? = None,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Resolution {
  let chain = []
  let base = if base is Some(_) { base } else { self.root_base }
  match self.hop(reference, base, chain, None, limits) {
    Found(location) =>
      { target: Some(location), chain, diagnostics: [], complete: true, }
    Failed(d, complete) => { target: None, chain, diagnostics: [d], complete, }
  }
}

///|
/// Follow a reference chain while `next` reports that a target is itself a
/// reference. Each later reference resolves against its owning resource URI.
/// Revisiting a location is a `ReferenceCycle`; chains longer than
/// `max_depth` are incomplete.
pub fn ResourceSet::follow(
  self : ResourceSet,
  reference : Reference,
  next : (Location) -> Reference?,
  base~ : UriReference? = None,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Resolution {
  let chain = []
  let seen : Set[String] = Set([])
  let mut base = if base is Some(_) { base } else { self.root_base }
  let mut current = reference
  let mut site : Location? = None
  while true {
    if chain.length() >= limits.max_depth() {
      return {
        target: None,
        chain,
        diagnostics: [limit_error("Reference chain length limit exceeded")],
        complete: false,
      }
    }
    match self.hop(current, base, chain, site, limits) {
      Failed(d, complete) =>
        return { target: None, chain, diagnostics: [d], complete, }
      Found(location) => {
        if !seen.add_and_check(location.identity()) {
          return {
            target: None,
            chain,
            diagnostics: [
              @json.Diagnostic::new(
                @json.ReferenceCycle,
                "Reference chain revisits " + location.identity(),
                path=location.pointer.tokens(),
              ),
            ],
            complete: true,
          }
        }
        match next(location) {
          Some(following) => {
            current = following
            base = location.resource
            site = Some(location)
          }
          None =>
            return {
              target: Some(location),
              chain,
              diagnostics: [],
              complete: true,
            }
        }
      }
    }
  }
  panic()
}
