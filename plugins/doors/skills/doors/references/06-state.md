# State

Reactive values in Doors: `Source[T]` (writable) and `Beam[T]` (read-only).

## Contents

- [Derivation vs Virtual DOM Diffing](#derivation-vs-virtual-dom-diffing)
- [Types](#types)
- [Creating Sources](#creating-sources)
- [Derived Sources (writable views)](#derived-sources-writable-views)
- [Derived Beams (read-only views)](#derived-beams-read-only-views)
- [Rendering Strategies](#rendering-strategies)
- [Reading](#reading)
- [Updating](#updating)
- [Equality & Skipping](#equality--skipping)
- [Consistency](#consistency)
- [Rules](#rules)
- [Related](#related)

## Derivation vs Virtual DOM Diffing

Doors does not have a virtual DOM. It doesn't render everything and diff. Instead, **derivation is the substitute**: you derive narrow, specific beams from one source of truth. When a source updates, only the beams whose derived value actually changed propagate. Only subscribers (Bind, Effect) to those changed beams re-render.

Use the same ladder for every reactive model, not only paths: the current owner routes on a branch key (often derived from a larger source), narrower derived sources/beams represent fields or child state, and `Bind`/`Effect` live only in fragments that render those values.

```
Source[Settings]         <- one source of truth
 ├─ Beam[units]          <- only fires when Units field changes
 ├─ Beam[days]           <- only fires when Days field changes
 ├─ Beam[isMetric]       <- derived from units, fires on metric/imperial toggle
 └─ Beam[isLongRange]    <- derived from days, fires at threshold crossing
```

When the user toggles units from metric to imperial:
- `Beam[units]` value changes → its subscribers re-render (charts that show temperature/wind speed)
- `Beam[days]` value unchanged → its subscribers do nothing (the days navigation)
- `Beam[isMetric]` changes → subscribers re-render
- `Beam[isLongRange]` unchanged → subscribers do nothing

This is why the tutorial dashboard can have 7 charts, a nav, and query params all driven from one path model — only the specific parts that actually changed re-render. No diff needed: derivation tracks what changed before rendering starts.

Compare to virtual DOM: you'd render the entire dashboard component tree, diff old vs new, find which `<span>`s changed, then patch. With derivation, you skip straight to re-rendering only the pieces that need it.

## Types

```go
type Source[T any] interface {
    Beam[T]
    Update(ctx context.Context, value T)
    XUpdate(ctx context.Context, value T) <-chan error
    Mutate(ctx context.Context, f func(T) T)
    XMutate(ctx context.Context, f func(T) T) <-chan error
    Route(routes ...RouteSource[T]) gox.EditorComp
}

type Beam[T any] interface {
    Read(ctx context.Context) (T, bool)
    Get() T
    Sub(ctx context.Context, onValue func(context.Context, T) bool) bool
    ReadAndSub(ctx context.Context, onValue func(context.Context, T) bool) (T, bool)
    Effect(ctx context.Context) (T, bool)
    Bind(f func(T) gox.Elem) gox.EditorComp
    RouteBeam(routes ...RouteBeam[T]) gox.EditorComp
    Watch(ctx context.Context, w Watcher[T]) (context.CancelFunc, bool)
}
```

A `Source` is also a `Beam` — every source can be read, subscribed, bound, and routed.

## Creating Sources

```go
func NewSource[T comparable](init T) Source[T]                            // uses == equality
func NewSourceEqual[T any](init T, equal func(new, old T) bool) Source[T] // custom equality
func NewSourceNoSkip[T comparable](init T) Source[T]                       // no-skip semantics
func NewSourceEqualNoSkip[T any](init T, equal func(new, old T) bool) Source[T]
```

`Source` and `Beam` values are handles. A struct field's zero value is nil; initialize it with `NewSource`, `DeriveSource`/`DeriveBeam`, or a parent-provided value before any `Bind`, `Effect`, `Read`, or `Update`.

## Derived Sources (writable views)

```go
func DeriveSource[T1 any, T2 comparable](source Source[T1], get func(T1) T2, set func(T1, T2) T1) Source[T2]
func DeriveSourceEqual[T1 any, T2 any](source Source[T1], get func(T1) T2, set func(T1, T2) T1, equal func(new, old T2) bool) Source[T2]
```

`get` extracts the derived value. `set` receives current parent + new derived, returns next parent.

```go
settings := doors.NewSource(Settings{Units: "metric", Days: 7})

units := doors.DeriveSource(settings,
    func(s Settings) string { return s.Units },
    func(s Settings, units string) Settings { s.Units = units; return s },
)
```

## Derived Beams (read-only views)

```go
func DeriveBeam[T1 any, T2 comparable](source Beam[T1], get func(T1) T2) Beam[T2]
func DeriveBeamEqual[T1 any, T2 any](source Beam[T1], get func(T1) T2, equal func(new, old T2) bool) Beam[T2]
```

```go
longRange := doors.DeriveBeam(settings, func(s Settings) bool { return s.Days > 7 })
```

### Practical derivation example (from tutorial)

A dashboard page has query params `units` (metric/imperial) and `days` (1-7). These live in the path model. Deriving narrow beams means each part of the UI only re-renders when its specific value actually changes:

```go
// Path model with query params
type Path struct {
    Route  Route          `path:"/ | /:CityID"`
    CityID int
    Units  *driver.Units  `query:"units"`
    Days   *int           `query:"days"`
}

func WeatherDashboard(path doors.Source[Path]) gox.Comp {
    city  := doors.DeriveBeam(path, func(p Path) int { return p.CityID })
    days  := doors.DeriveBeam(path, func(p Path) int { return p.days() })
    units := doors.DeriveBeam(path, func(p Path) driver.Units { return p.units() })
    ...
}
```

Now in rendering:
- `days.Bind(...)` only rerenders the days navigation when days changes — units changes don't touch it
- `units.Bind(...)` only rerenders the units navigation when units changes — days changes don't touch it
- A chart that uses `Effect(ctx)` on both `days` and `units` rerenders only when the chart's specific combination of params changes

The path model is the single source of truth. Each derived beam exposes one narrow slice. Each subscriber reacts only to its slice. This is how Doors achieves precision updates without a virtual DOM.

### Derivation rules

**Validate at the boundary.** Derivation functions are the natural place to clamp, default, and sanitize. The raw URL/query value enters the path model; the derived beam exposes only safe values:

```go
func (p Path) days() int {
    if p.Days == nil { return 7 }            // default nil to safe default
    return min(max(*p.Days, 1), 7)           // clamp to valid range
}
```

**No external calls.** `get()` and `set()` functions must be pure, synchronous transformations — no DB queries, HTTP calls, or I/O. They run frequently and their result must be immediately available. If you need to load data that depends on derived state, create a separate data source and use `Effect` to react when the derivation changes:

```gox
~>(new(doors.Door)) ~func {
    days, _ := d.days.Effect(ctx)      // ← pure, immediate, bounded
    units, ok := d.units.Effect(ctx)
    if !ok { return nil }
    svg, _ := weather.Temperature(ctx, city, units, days)
    ...
}
```

**State holds identifiers, not bulk data.** Keep IDs, filters, settings, selections in Doors state. Query backing data during render and forget it. Storing small config-like records (e.g., user access settings) is fine; storing table data (product lists, search results) rarely makes sense. Storing gox elements/components is possible but be cautious — prefer generating markup from state during render.

## Rendering Strategies

Two approaches to connecting reactive state to UI. Both are built on `Door` internally.

### Bind — declarative, single-source reactivity

You declare the connection: "this fragment is driven by this value." The callback receives the value as a parameter — the framework handles tracking and wiring. Only this fragment rerenders on change.

```gox
type counter struct {
    state doors.Source[int]
}

elem (c counter) Main() {
    <button (doors.AClick{
        On: func(ctx context.Context, rp doors.RequestPointer) bool {
            c.state.Mutate(ctx, func(i int) int { return i + 1 })
            return false
        },
    })>Add</button>

    ~(c.state.Bind(c.count))
}

elem (c counter) count(i int) {
    ~(if i == 0 {  ← Click! } else { ~(" ", i) })
}
```

Use when: you want explicit, self-documenting wiring between a value and its fragment.

### Effect — inline, multi-source reactivity

You read values imperatively inside a dynamic container. The framework tracks which values you read and rerenders the container when any of them change. Outer-facing: you pull values yourself.

```gox
~>(new(doors.Door)) ~func {
    days, _ := d.days.Effect(ctx)
    units, ok := d.units.Effect(ctx)
    if !ok {
        return nil
    }
    values, _ := driver.Weather.Temperature(ctx, city, units, days)
    svg, _ := driver.ChartLine(values.Values, values.Labels, units.Temperature())
    return <img src=(svg)/>
}
```

Use when: you prefer pulling values inline over declaring callback wiring, or when multiple related values must be read together before rendering (e.g. query params → data fetch → render).

Keep Effect boundaries small. An Effect is not a React component — it re-renders its entire container when any tracked value changes. It's normal and expected to have multiple Effect boundaries in a single component/element, each covering the narrowest set of values it needs. This aligns with the core idea: derive state to the smallest piece, update only what changed.

Only check the last `ok` — `Effect` fails only on canceled context, so if the last succeeds, earlier ones did too.

### Route / RouteBeam — pick one view based on value

```gox
~(s.section.Route(
    doors.RouteValue(SectionProfile).Comp(ProfilePanel{}),
    doors.RouteValue(SectionBilling).Comp(BillingPanel{}),
    doors.RouteDefaultComp(ProfilePanel{}),
))
```

Fragment swaps only when active route changes. Value changes that keep matching the same route do not rerender the route fragment. Within a matched route, use `Bind`, `Effect`, or derived values for the narrower data that fragment actually renders.

A `Source` is also a `Beam`, so `source.RouteBeam(routes...)` is available when the route branches only need read-only access.

**Render methods** on match builders produce route branches:

| Method | Signature | Receives |
|--------|-----------|----------|
| `.Comp(comp)` | fixed `gox.Comp` | no reactive value |
| `.Beam(render)` | `func(Beam[T]) gox.Elem` | live read-only beam |
| `.Bind(render)` | `func(T) gox.Elem` | raw value directly (shorthand for Beam + bind) |
| `.Source(render)` | `func(Source[T]) gox.Elem` | live writable source |

`.Bind` is equivalent to `.Beam(func(b Beam[T]) gox.Elem { return b.Bind(render).Main() })`.

**Default fallbacks** always match (place last):

- `RouteDefaultComp(comp)` — fixed component
- `RouteDefaultBeam(render)` — read-only beam
- `RouteDefaultBind(render)` — raw value (shorthand for RouteDefaultBeam + bind)
- `RouteDefault(render)` — writable source, only inside `source.Route(...)`

### Sub — manual subscription

`Sub` subscribes to future changes and fires immediately with the current value:

```go
beam.Sub(ctx, func(ctx context.Context, v T) bool {
    door.Inner(ctx, render(v))
    return false // keep subscribed
})
```

`ReadAndSub(ctx, fn)` returns the current value as a return value; the callback fires only for subsequent updates. `Sub` fires immediately with the current value and again on every update. Both end when the callback returns `true` or the owning parent unmounts.

## Reading

- `Read(ctx)` — render-consistent value, needs Doors context
- `Get()` — latest stored value, no context, no consistency guarantees
- `ReadAndSub(ctx, fn)` — current value + subscribe to future changes
- `Sub(ctx, fn)` — subscribe to future changes only (no initial read)

## Updating

- `source.Update(ctx, value)` — set new value
- `source.Mutate(ctx, fn)` — compute from old value
- `XUpdate`/`XMutate` — return completion channel (don't wait during render)

## Equality & Skipping

Default: `Source` suppresses equal updates (`==` comparison). Customize with `*Equal` constructors. Equality returns `true` → no propagation.

Default: in-flight propagation can be skipped by newer updates (UI prefers latest state). Use `NoSkip` to keep propagating when every committed update must complete. NoSkip does NOT bypass equality — equal updates are still suppressed.

## Consistency

During one render/update cycle, a Door subtree sees one coherent view of a `Source` and all derived sources/beams. Parent and children never see different versions halfway through the same render. Effect + Bind + subscriptions observe the same value within one cycle.

`Read` and `Sub` capture the observable value for the current cycle. Mutating the same source later in the same cycle (including in the page factory) won't be visible until the next cycle. To redirect or adjust the initial location in the page factory, use `Get()` to inspect the current value (it does not freeze), call `Update` or `Mutate`, and place `Sub`/`ReadAndSub` **after** the mutation.

## Rules

- One source of truth, derive smaller pieces. Derivation replaces virtual DOM diffing.
- Derive functions must be pure — no external calls, no I/O. Clamp/bound at the derivation point.
- Keep state as "origin" values: IDs, filters, settings, selections. Small config records ok; table data (lists, results) rarely makes sense. Storing components is possible but be cautious.
- Query data while rendering or handling events. Render and forget. Don't cache large records in page memory.
- Treat source values as immutable — replace with a new value, never mutate in place.
- `Read(ctx)` for render-consistent values, `Get()` only outside render guarantees.
- `NoSkip` only when every in-flight committed update must finish. Doesn't bypass equality.

## Related

- [routing.md](./05-routing.md) — `RouteModel`, URL routing as source routing
- [door.md](./07-door.md) — `Door` (what Bind/Effect use internally)
