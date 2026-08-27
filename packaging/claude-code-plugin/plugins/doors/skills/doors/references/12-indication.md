# Indication

Temporary client-side DOM feedback while a request is in flight. Applied at request start, restored at request end.

## Interface

```go
type Indicators interface {
    Indicators() []Indicator
    Joiner[Indicators]
}
```

Each indicator type implements `Indicators` directly. Combine with `.And(...)` or `JoinIndicators(...)`.

## Kinds

| Helper | Effect |
|--------|--------|
| `IndicateContent(html)` | Replace content with `html` (innerHTML) |
| `IndicateAttr(name, value)` | Set attribute `name=value` |
| `IndicateClass(class)` | Add CSS class(es) |
| `IndicateClassRemove(class)` | Remove CSS class(es) |

`IndicateContent` writes to `innerHTML` without escaping; pass only trusted HTML.

## Targets

Suffix on each helper:

| Suffix | Target |
|--------|--------|
| *(none)* | Event source element |
| `Query(q)` | First CSS match |
| `QueryAll(q)` | All CSS matches |
| `QueryParent(q)` | Closest matching ancestor |

```go
doors.IndicateAttrQuery("#loader", "aria-busy", "true")
doors.IndicateClassQueryAll(".row", "pending")
```

Target and parent selectors need an event element and select nothing without one — for `AHook`/`ARawHook` calls and `ActionIndicate` outside event attr or `ALink` action lists, only the `Query`/`QueryAll` variants apply.

## Struct Form

For shared selectors or multiple changes:

```go
sel := doors.SelectorQuery("#card")
Indicator: doors.JoinIndicators(
    doors.IndicatorAttr{Selector: sel, Name: "data-state", Value: "saving"},
    doors.IndicatorClass{Selector: sel, Class: "pending"},
    doors.IndicatorContent{Selector: sel, Content: "Saving..."},
)
```

`Selector` is optional; the zero value selects the event element.

## Selectors

```go
func SelectorTarget() Selector            // event element
func SelectorQuery(q string) Selector     // first match
func SelectorQueryAll(q string) Selector  // all matches
func SelectorQueryParent(q string) Selector // closest ancestor match
```

## Behavior

- Indication starts when request actually begins on client (scopes can delay/cancel)
- On request end: temporary attributes removed, added classes removed, removed classes restored, content put back
- Overlapping indications on same element queue — when one ends, next takes over
- Fields the next indication doesn't touch fall back to original value (not previous indication's value)
- A handler can keep the request — and its indication — pending past its return with `doors.HoldSettle(ctx)`; the indicator is restored when the hold is released. See [door.md](./07-door.md)

## Combining

```go
Indicator: doors.IndicateClass("loading").
    And(doors.IndicateAttrQuery("#loader", "aria-busy", "true"))
```

## ActionIndicate

Fixed-duration indication, not tied to request lifecycle:

```go
doors.ActionIndicate{
    Indicator: doors.IndicateClass("pending"),  // required
    Duration:  300 * time.Millisecond,          // required; truncated to ms
}
```
See [actions.md](./13-actions.md).

## Related

- [events.md](./09-events.md) — `Indicator` field on event attrs
- [navigation.md](./10-navigation.md) — `Active.Indicator` on links
- [scopes.md](./11-scopes.md) — Scopes pair with indication for polished UX
- [door.md](./07-door.md) — `HoldSettle` keeps indication pending
