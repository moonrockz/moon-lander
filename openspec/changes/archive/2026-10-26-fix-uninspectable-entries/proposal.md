## Why

On Windows, a run that starts in a folder with no workspace marker above it can fail
with exit code 1 (bead `lander-4us.45`). The enclosing-workspace search walks up to the
drive root and asks for each listing. The native and js host adapters inspect the kind
of each listed entry, and one locked system file such as `D:/pagefile.sys` makes the
inspection fail. The adapters then raise the error, so the full load fails, although
discovery never needs that entry. The Windows CI of PR #93 found it. The group 9
acceptance tests set a boundary to hide it.

## What Changes

- `EntryKind` gets the case `Inaccessible`: the host lists the entry but cannot inspect
  its kind, for example a file that another process locks, a link loop, or a missing
  permission.
- The native and js host adapters record such an entry as `Inaccessible` and do not
  raise. An entry that disappears between the listing and the inspection is not in the
  listing.
- `FileTree::is_file` treats an `Inaccessible` entry with the exact name as not known
  until the host answers for it, and the new `FileTree::file_request` asks for that
  file. A wildcard member pattern treats the entry as a possible directory. The load
  reads that path before it counts the candidates, and the host reports the real error. So an inaccessible candidate is
  still an error, and discovery never drops a configuration file without a report.
- An inaccessible entry that is not a candidate has no effect on the load.
- The acceptance tests of the workspace selectors no longer need a boundary.

## Capabilities

### Modified Capabilities

- `configuration-core`: directory listings from the host adapters.
- `configuration-conventions`: walk-up and member search over inaccessible entries.

## Impact

`@config.EntryKind` gets a new case, so an exhaustive `match` outside this repository
must add it. Before the first release this needs no compatibility step. Loads that
failed because of an unrelated entry now succeed. Loads with an inaccessible candidate
still fail with the error of the host.
