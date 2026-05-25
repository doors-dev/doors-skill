# Scopes

Client-side request scheduling. Control what happens when events overlap.

## Why

- Prevent double-clicks on submit buttons
- Queue repeated actions
- Debounce typing
- Make one action wait for a related group
- Drop stale in-flight work

Scopes run on the **client**, before the backend request begins.

## Interface

```go
type Scopes interface {
    Scopes(core core.Core) []Scope
    Joiner[Scopes]
}
```

`ScopeBlocking`, `ScopeSerial`, `ScopeDebounce`, and `ScopeLatest` implement `Scopes` directly. `ScopeFrame` and `ScopeConcurrent` are factories; call `.Scope(...)` to get a `Scopes` value. Combine scopes with `.And(...)` or `JoinScopes(...)`.

## Scope Types

### ScopeBlocking

Only one request at a time. Later events are rejected.

```go
scope := &doors.ScopeBlocking{}
Scope: scope
```

This is a client-side scheduling policy. Reusing the same activated hook already serializes that hook on the backend; `ScopeBlocking` prevents overlapping client requests before they are sent.

### ScopeSerial

Queue accepted events, run one after another. First starts immediately; later events start in arrival order after the previous one completes. Unlike blocking, serial does not drop later accepted events.

```go
scope := &doors.ScopeSerial{}
```

### ScopeDebounce

Wait for quiet period before sending. Keeps only the latest pending event in a burst.

```go
scope := &doors.ScopeDebounce{
    Duration: 300 * time.Millisecond,  // quiet period
    Limit:    600 * time.Millisecond,  // max wait (0 = no limit)
}
```

`Duration` is the resettable wait time. `Limit` is the maximum total wait; `0` means no limit. Without a limit, only the final burst event runs.

### ScopeLatest

Cancel previous in-flight work, keep only newest. Unlike debounce, replaces work already in progress.

```go
scope := &doors.ScopeLatest{}
```

Cancellation is client-side. The previous request may already have reached the server, so do not rely on `ScopeLatest` to protect writes; use it to end stale indication, ignore stale results, and keep the newest interaction in control of the UI.

### ScopeFrame

Separate normal events from a barrier event.

```go
frame := &doors.ScopeFrame{}
frame.Scope(false) // normal event — waits for earlier, can overlap with other normals
frame.Scope(true)  // frame event — waits for all, blocks new events while pending/running
```

A frame event waits for earlier events in the same shared frame scope. Once the frame event is pending or running, new events in that frame scope are blocked.

### ScopeConcurrent

Allow overlap only within same group ID.

```go
scope := &doors.ScopeConcurrent{}
scope.Scope(1) // group 1 — overlaps with other group 1 events
scope.Scope(0) // group 0 — blocked by group 1, blocks group 1
```

If the scope is occupied by one group, an event from a different group is canceled. Use it when related controls may overlap with each other, but a different action must not overlap with them.

## Sharing (reusing scope instances)

Same scope instance → handlers coordinate with each other:

```gox
~{
    block := &doors.ScopeBlocking{}
}
<button (doors.AClick{Scope: block, On: ...})>One</button>
<button (doors.AClick{Scope: block, On: ...})>Two</button>
```

Both buttons share one blocking rule — only one click at a time.

## Pipelines

Scopes chain with `.And(...)` (order matters):

```go
Scope: frame.Scope(false).And(debounce).And(serial)
// OR
Scope: doors.JoinScopes(frame.Scope(false), debounce, serial)
```

Each scope sees the event only after the previous accepted it.

## Rules

- Client-side only — shapes whether/when a request is sent
- Not a backend permission or one-shot guarantee
- Pair with indication for polished UX
- `ScopeBlocking` is the simplest "prevent double-submit"
- `ScopeLatest` may cancel in-flight client work but request may already reach server

## Related

- [events.md](./09-events.md) — Event attr `Scope` field
- [indication.md](./12-indication.md) — `Indicator` pairs naturally with scopes
