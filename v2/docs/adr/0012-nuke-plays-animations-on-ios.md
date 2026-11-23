# 0012: On iOS the adapter plays animations, in an image view it supplies

Status: accepted. Amends [0004](0004-android-adapter-displays-the-image.md)
for animated images; for stills, 0004 stands.

## Context

2.0 first decoded every frame of a GIF, APNG or animated WebP with ImageIO
into a `UIImage.animatedImage`, so the seam could stay "the adapter returns
a `UIImage`, the view shows it". That cost memory in proportion to the whole
animation, and an animation over 64 MB decoded was shown as its first frame.

Nuke 14 has a player (NukeUI): frames are decoded as they are shown, held in
a pool with a budget shared by every animation on screen, and shared between
views of the same animation. It plays through its own `UIImageView`
subclass, and from an animation object that is not a `UIImage`.

## Decision

Use Nuke's player. The seam gains what that takes and no more:

- `makeImageView`: the adapter supplies the image view of each TurboImage
  view (Nuke: `AnimatedImageView`).
- The completion delivers the still, as before, and an opaque `animation`
  for an animated image.
- `displayImage:animation:inImageView:`: the view hands both back to the
  adapter to show the result of a load.

The view still decides what is on screen and when ([0010](0010-view-lifecycle-in-the-core.md)),
and still sets placeholders and clears the image itself, through `image`.
The seam stays plain Objective-C with no Nuke type in it
([0003](0003-plain-objc-seam-on-ios.md)).

Three of Nuke's defaults are overridden, for parity with Android and with
what 2.0 did before:

- Animations loop for as long as they are shown. Nuke follows the file's
  loop count, and would play a GIF that declares none once.
- Nuke's own animation parsing is off and the adapter attaches the animation
  itself: Nuke attaches none to a downscaled request, which is nearly every
  TurboImage request, and it also plays HEIC and AVIF sequences.
- Frames are sized by the same rule as the still: for the view, unless
  `allowDownscaling` is off.

## Consequences

- No frame limit; memory is bounded by Nuke's pool (5% of the device's
  memory, at most 128 MB, beside the image cache).
- The adapter paints frames without asking the view, which 0004 says only
  Android does. It can only do so for an animation the view passed to
  `displayImage:`, and setting `image` stops it, so the view keeps its veto;
  that rule is now part of the seam's contract. The lifecycle model does not
  model frames.
- An animation shows a still while Reduce Motion is on or Auto-Play Animated
  Images is off, and pauses outside a window, hidden or transparent. Android
  does neither.
- Every TurboImage view ignores Smart Invert (`accessibilityIgnoresInvertColors`),
  stills included: the image view sets it.
- CocoaPods vendors a second framework, `NukeUI.xcframework`. The tarball is
  about 21 MB (14.2 MB with Nuke alone).
- A replacement adapter has two more methods to implement; one that plays
  no animations returns a plain `UIImageView` and sets `image`.

More: RFC §4.5b; `TIImageLoading.h`; `NukeImageLoader.swift` (`makeImageView`, `display`).
