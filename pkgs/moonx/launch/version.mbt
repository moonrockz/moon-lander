///|
/// A valid release constant generated from the root version by versions.mbtx.
/// No user input or public constructor can create another version value.
priv struct PackageVersion(String)

///|
let package_version : PackageVersion = PackageVersion("0.10.0")

///|
fn PackageVersion::text(self : PackageVersion) -> String { self.0 }
