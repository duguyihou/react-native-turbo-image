# 0003: The iOS seam is plain Objective-C, and the adapter is found by name

Status: accepted. Amended by [0014](0014-the-loader-seam-is-internal.md): apps no longer replace the loader

## Context

The view is ObjC++ (it speaks to Fabric and to the C++ core). Nuke is
Swift. Swift/C++ interop would have to be switched on for every target that
imports the Swift module, including the app's.

## Decision

The seam (`ios/LoaderAPI/include`) is plain ObjC with no C++ and no Nuke
type; these are the module's public headers. The ObjC++ view converts the
core's result into a `TIImageRequest`; the processing step crosses as a
block. `TIImageLoaderRegistry` finds the bundled adapter with
`NSClassFromString(@"TurboImageNukeLoader")`, because importing the Swift
target from the seam would invert the layering and create a SwiftPM cycle.

## Consequences

- A typo in the class name fails at run time, not at link time. The example app exercises the lookup in CI.
- An app replaces the loader by assigning `TIImageLoaderRegistry.sharedLoader`.
- SwiftPM requires the Fabric target to name a public-headers directory. It holds only that target's two plain-ObjC class headers (`ios/Fabric/include`); the C++ factory header stays private on both paths.

More: RFC §4.7.
