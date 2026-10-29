///|
/// Describe a kernel without installing or executing it. Implementations return
/// an immutable descriptor with already parsed names and aliases.
pub(open) trait KernelDescriptor {
  /// Return the canonical name, aliases and optional language label.
  fn kernel_info(Self) -> KernelInfo
}

///|
pub impl KernelDescriptor for KernelInfo with fn kernel_info(self) {
  self
}

///|
pub extend KernelInfo with KernelDescriptor::{kernel_info}

///|
/// An immutable registry and source policy shared by all codec operations.
struct Codec {
  registry : KernelRegistry
  source_mode : SourceMode
}

///|
/// Use the standard registry, or start a custom registry with the supplied
/// default descriptor. Markdown is available in either case.
pub fn Codec::new(
  default? : &KernelDescriptor,
  source_mode~ : SourceMode = Normalized,
) -> Codec raise FormatError {
  let registry = match default {
    None => KernelRegistry::standard()
    Some(descriptor) => {
      let info = descriptor.kernel_info()
      KernelRegistry::KernelRegistry([info], default_kernel=info.name())
    }
  }
  { registry: with_markdown(registry), source_mode, }
}

///|
/// Preserve empty cells and source boundary lines at every codec operation.
pub fn Codec::lossless(default? : &KernelDescriptor) -> Codec raise FormatError {
  Codec::new(default?, source_mode=Lossless)
}

///|
/// Register a descriptor in a new codec. Name or alias collisions raise the
/// existing DuplicateKernelName error. The original codec remains unchanged.
pub fn Codec::with_kernel(
  self : Codec,
  descriptor : &KernelDescriptor,
) -> Codec raise FormatError {
  let info = descriptor.kernel_info()
  let registry = KernelRegistry::KernelRegistry(
    ReadOnlyArray::from_iter(self.registry.kernels().iter().concat([info].iter())),
    default_kernel=self.registry.default_kernel(),
  )
  { ..self, registry, }
}

///|
/// Return the immutable registry used by this codec.
pub fn Codec::registry(self : Codec) -> KernelRegistry {
  self.registry
}

///|
/// Return the source policy used by this codec.
pub fn Codec::source_mode(self : Codec) -> SourceMode {
  self.source_mode
}

///|
/// Construct a cell with this codec's source policy and canonical kernel.
/// An omitted kernel uses the configured default.
pub fn Codec::cell(
  self : Codec,
  source : String,
  kernel? : KernelName,
) -> Cell raise FormatError {
  let name = kernel.unwrap_or(self.registry.default_kernel())
  guard self.registry.resolve(name.to_string()) is Some(kernel) else {
    raise UnknownKernel(name.to_string())
  }
  Cell::Cell(source, kernel~, source_mode=self.source_mode)
}

///|
/// Construct a notebook using this codec's registrations.
pub fn Codec::notebook(
  self : Codec,
  cells : ReadOnlyArray[Cell],
  metadata~ : Metadata = Metadata::empty(),
) -> Notebook raise FormatError {
  Notebook::Notebook(cells, registry=self.registry, metadata~)
}

///|
/// Read source with this codec's registry and source policy.
pub fn Codec::parse(self : Codec, source : String) -> Notebook raise FormatError {
  parse(source, registry=self.registry, source_mode=self.source_mode)
}

///|
/// Write a notebook with this codec's source policy. The notebook retains its
/// effective registry, including definitions supplied by document metadata.
pub fn Codec::write(self : Codec, notebook : Notebook) -> String raise FormatError {
  notebook.to_string(source_mode=self.source_mode)
}
