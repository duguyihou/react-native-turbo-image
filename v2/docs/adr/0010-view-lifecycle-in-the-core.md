# 0010: The view lifecycle is a state machine in the core

Status: accepted

## Context

What a view shows depends on the order of five things: props change, a
load starts, the loader calls back, a placeholder finishes decoding on
another thread, the view is reused. Both native views answered that with the
same flags, mirrored by hand, with comments saying "same rule as the iOS
view". Most lifecycle bugs were found there, and no unit test could reach
either copy.

## Decision

`turboimage::ViewLifecycle` holds the state (what is shown, the token of
the load in flight, the placeholder generation) and decides. Each step takes
what happened and returns an ordered list of effects: cancel the load, clear
the image, start a load, emit an event. Each view carries the effects out in
one function and owns only what touches a platform type. On Android the state
is four longs in a `LongArray`, so there is no native handle.

## Consequences

- One copy, tested in GoogleTest, including a walk through every order of events to a fixed depth.
- The views cannot drift apart in a rule; they can still differ in how they carry out an effect, and in the one place the platforms really differ (who paints a loaded image, [ADR 0004](0004-android-adapter-displays-the-image.md)).
- Android pays a JNI call per step and per progress callback.
- An adapter may call back inside the call that starts a load, so `StartLoad` must stay the last effect of its list.

More: `cpp/include/turboimage/ViewLifecycle.h`; RFC §4.3, §4.4a, §4.4d.
