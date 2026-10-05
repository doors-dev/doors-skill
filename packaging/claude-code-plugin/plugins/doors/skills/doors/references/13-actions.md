# Actions

Client-side effects triggered from Go. Use when the browser should do something imperative (scroll, emit to JS, hard navigate, timed indication).

Prefer normal rendering/state for durable UI changes. Prefer `Setter` for shared attributes across elements.

## Trigger Points

```go
// Error channel optional; ignore it for fire-and-forget
doors.Call(ctx, action)

// Capture the client result with Into (don't wait during render)
var v T
ch := doors.Call(ctx, doors.ActionEmit[T]{Name: "n", Arg: arg}.Into(&v))

// Event attrs: Before, r.After(...), OnError
```

## Action Types

### ActionEmit — call JS handler

```go
type ActionEmit[T any] struct {
    Name string   // name registered with $on(name, handler)
    Arg  any      // string → string, []byte → ArrayBuffer, else JSON; nil → null
}
```

Handler lookup starts at the Door the action is dispatched from and walks out to the root — nearest matching handler wins. The action fails when no handler is reachable. Handlers may return a value or a Promise; the resolved value is what `Into` decodes.

When `ActionEmit` runs from `OnError`, the `$on(...)` handler receives the hook error as its second argument: `(arg, err)`.

An emit issued by the same render that inserts a managed script can arrive before that script registers its `$on` handler and fail with `handler … not found`. When it matters, have the script call a `$hook` after registering, and emit from that hook's handler (see `15-javascript.md`).

### ActionScroll — scroll into view

```go
type ActionScroll struct {
    Selector string
    Options  any  // passed to scrollIntoView(), e.g. map[string]any{"behavior": "smooth", "block": "center"}
}
```

Scrolls the first matching element into view. If no element matches, the action fails (error on the completion channel).

### ActionIndicate — fixed-duration indication

```go
type ActionIndicate struct {
    Indicator Indicators
    Duration  time.Duration
}
```

Not tied to request lifecycle. Lasts for `Duration`. Only Query/QueryAll indicator variants apply here — an event element exists only in event attr and `ALink` action lists, not in a direct `Call`.

### ActionTime — read the client clock

```go
var now time.Time
err := <-doors.Call(ctx, doors.ActionTime{}.Into(&now)) // in a handler or doors.Go, never during render
```

The reading keeps the browser's UTC offset, formatted like event timestamps.

### Location actions — hard navigation (full page load)

```go
type ActionLocationReload struct{}                         // reload current page
type ActionLocationAssign struct{ Model any }             // push + load model
type ActionLocationReplace struct{ Model any }            // replace + load model
type ActionLocationRawAssign struct{ URL string }         // literal absolute URL, push
type ActionLocationRawReplace struct{ URL string }        // literal absolute URL, replace history entry
```

For in-app navigation, prefer `ALink` or updating the `RouteModel` source.

## Combining

```go
r.After(doors.ActionScroll{Selector: "#top"}.
    And(doors.ActionIndicate{
        Indicator: doors.IndicateClass("pending"),
        Duration:  300 * time.Millisecond,
    }))

// or
r.After(doors.JoinActions(
    doors.ActionScroll{Selector: "#top"},
    doors.ActionIndicate{...},
))
```

## Call Results

```go
var picked string
ch := doors.Call(ctx, doors.ActionEmit[string]{Name: "pick", Arg: "hello"}.Into(&picked))
err, ok := <-ch  // ok==false when canceled; picked valid after nil
```

- `Call(ctx, action) <-chan error`: nil = success, error = build/client/decode failure, closed empty = canceled
- Match failures with `errors.Is`: `ErrExecution` = action reached the browser and failed there, `ErrTerminated` = instance ended first; location actions can also yield `ErrPathModel`/`ErrPathEncode` (see [routing](./05-routing.md))
- `ActionEmit[T]` declares its result type; `.Into(&dst)` arms decoding. Fire-and-forget: `ActionEmit[any]{...}` without Into
- `Emitter` event methods return `ActionInto[int]` — `.Into(&n)` captures hook requests triggered (any failure fails the call); `Setter.Set` counts live elements reached. See [element handles](./17-element-handles.md).
- Into has no effect inside Before/After/OnError lists (no result transport)
- Don't wait during render — use `Go` or goroutine with `DetachedContext`

## OnError

`OnError` runs for client-visible hook failures (network, server, bad request). NOT for scope cancellations or expired hooks. A stopped instance is handled by reloading the page instead.

## Rules

- Prefer rendering/state over actions for durable UI changes
- Ignore the `Call` error channel for fire-and-forget; capture results with `Into`
- `$on(...)` handlers may return a Promise
- Location actions = hard navigations (full reload). Use `ALink`/mutate source for in-app.
- Actions run in order within a list. Location actions deferred to end of current client turn.

## Related

- [javascript.md](./15-javascript.md) — `$on`, `ActionEmit`
- [indication.md](./12-indication.md) — `ActionIndicate`, indicator types
- [navigation.md](./10-navigation.md) — `ALink` vs location actions
- [shared-attr.md](./17-element-handles.md) — element handles: `Setter`, `Emitter` and their `ActionInto[int]` semantics
