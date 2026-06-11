# Actions

Client-side effects triggered from Go. Use when the browser should do something imperative (scroll, emit to JS, hard navigate, timed indication).

Prefer normal rendering/state for durable UI changes. Prefer `AShared` for shared attributes across elements.

## Trigger Points

```go
// Fire-and-forget (no result)
doors.Call(ctx, action)

// With result channel (don't wait during render)
ch := doors.XCall[T](ctx, action)

// Event attrs: Before, r.After(...), OnError
```

## Action Types

### ActionEmit — call JS handler

```go
type ActionEmit struct {
    Name string   // name registered with $on(name, handler)
    Arg  any      // argument passed to handler
}
```

Handler search walks outward through the Door tree — nearest matching handler wins. Handlers must be synchronous (returning a Promise fails the action).

When `ActionEmit` runs from `OnError`, the `$on(...)` handler receives the hook error as its second argument: `(arg, err)`.

### ActionScroll — scroll into view

```go
type ActionScroll struct {
    Selector string
    Options  any  // passed to scrollIntoView(), e.g. map[string]any{"behavior": "smooth", "block": "center"}
}
```

Scrolls the first matching element into view. If no element matches, nothing happens.

### ActionIndicate — fixed-duration indication

```go
type ActionIndicate struct {
    Indicator Indicators
    Duration  time.Duration
}
```

Not tied to request lifecycle. Lasts for `Duration`. Use with `SelectorTarget()` cautiously — from `Call`/`XCall` there is no event target.

### Location actions — hard navigation (full page load)

```go
type ActionLocationReload struct{}                         // reload current page
type ActionLocationAssign struct{ Model any }             // push + load model
type ActionLocationReplace struct{ Model any }            // replace + load model
type ActionLocationRawAssign struct{ URL string }         // literal URL
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

## XCall Results

```go
type CallResult[T any] struct {
    Ok  T
    Err error
}
ch := doors.XCall[string](ctx, doors.ActionEmit{Name: "pick", Arg: "hello"})
res, ok := <-ch  // ok==false when canceled
```

- Cancel `ctx` → best-effort cancellation, channel closes without value
- Don't wait during render — use `Go` or goroutine with `DetachedContext`
- For most actions use `json.RawMessage` as `T`; `ActionEmit` is the main case for real types

## OnError

`OnError` runs for client-visible hook failures (network, server, bad request). NOT for scope cancellations or expired hooks. A stopped instance is handled by reloading the page instead.

## Rules

- Prefer rendering/state over actions for durable UI changes
- `Call` for fire-and-forget, `XCall` mainly with `ActionEmit`
- `$on(...)` handlers must stay synchronous
- Location actions = hard navigations (full reload). Use `ALink`/mutate source for in-app.
- Actions run in order within a list. Location actions deferred to end of current client turn.

## Related

- [javascript.md](./15-javascript.md) — `$on`, `ActionEmit`
- [indication.md](./12-indication.md) — `ActionIndicate`, indicator types
- [navigation.md](./10-navigation.md) — `ALink` vs location actions
- [shared-attr.md](./17-shared-attr.md) — `AShared` as alternative to actions
