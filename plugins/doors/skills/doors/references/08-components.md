# Components

Doors components are Go structs with `Main() gox.Elem`. There is no virtual DOM — every component is **static by default**. `Main()` renders once and stays. Re-rendering is explicit: `Bind` and `Effect` fragments re-render automatically, while `Sub` callbacks fire on every value change unconditionally. The rest of the tree is untouched.

## Component Model

```gox
func NewCounter() gox.Comp {
    return counter{state: doors.NewSource(0)}
}

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

    ~(c.state.Bind(c.count))   // ← only this fragment rerenders
}

elem (c counter) count(i int) {
    ~(if i == 0 {  ← Click! } else { ~(" ", i) })
}
```

The struct is created once when placed in the tree and persists. `Main()` is called once. The `<button>` stays forever. Only the `Bind` fragment re-renders when `c.state` changes. Nothing else in this component or its parent is affected.

Re-renders happen only through these APIs:
- `someBeam.Bind(fn)` — rerenders the returned fragment when value changes
- `someBeam.Effect(ctx)` inside a dynamic container — rerenders the container
- `door.Inner(ctx, ...)`, `door.Outer(ctx, ...)`, `door.Static(ctx, ...)` — replaces door content
- `door.Reload(ctx)` — rerenders current door content
- Updating a source that has subscribers downstream

Constructors exist to hide internals. Without `NewCounter()`, every caller must write `counter{state: doors.NewSource(0)}`. The constructor keeps `doors.NewSource` private to the component.

## Rendering Strategies

Both are built on `Door` internally. Use the right one for the situation.

### Bind — declarative, single-source reactivity

You declare the connection: "this fragment is driven by this value." The callback receives the value as a parameter — the framework handles tracking and wiring. Only this fragment re-renders on change. The counter above is a Bind example: `c.state.Bind(c.count)`.

Use when: you want explicit, self-documenting wiring between a value and its fragment.

### Effect — inline, multi-source reactivity

You read values imperatively inside a dynamic container. The framework tracks which values you read and re-renders the container when any of them change. Outer-facing: you pull values yourself.

```gox
~>(new(doors.Door)) ~func {
    days, _ := d.days.Effect(ctx)
    units, ok := d.units.Effect(ctx)
    if !ok { return nil }

    svg, _ := weatherChart(ctx, city, units, days)
    return <img src=(svg)/>
}
```

Use when: you prefer pulling values inline over declaring callback wiring, or when multiple related values must be read together before rendering.

Keep Effect boundaries small. An Effect is not a React component — it re-renders its entire container on any change. It's normal to have multiple Effect boundaries in a single component, each covering the narrowest set of values. This aligns with the core idea: derive state to the smallest piece.

Only check the last `ok` — `Effect` fails only on canceled context.

### Comparison

| | Bind | Effect |
|---|------|--------|
| Style | Declarative: value flows in via callback | Inline: pull values imperatively |
| Re-render | Fragment only | Container + children |
| Best for | Explicit value → fragment wiring | Interdependent values read together |

## Structuring

### Fields

```gox
type placeSelector struct {
    title    string                     // configuration
    search   func(string) ([]Place, error)  // dependency
    selected doors.Source[Place]        // reactive state from parent
    scope    doors.Scopes               // shared scheduling
}
```

### `any` fields for text or markup

Fields typed `any` accept strings, numbers, and `<>...(markup)...</>` fragments:

```gox
type navLink struct {
    model any
    text  any   // "Home" or <>~("Day ", days)</>
}

elem (l navLink) Main() {
    ~>doors.ALink{Model: l.model} <a>~(l.text)</a>
}
```

### State ownership

- **Local**: create `Source` in the constructor, store on struct field
- **Shared**: accept `Source`/`Beam` from parent via constructor/field
- **Derived**: `DeriveSource`/`DeriveBeam` from a parent source, also in the constructor

Do not add a `doors.Source`/`doors.Beam` field and leave initialization implicit. Snippets with source fields should show an ordinary Go constructor/factory or parent wiring that gives the field a non-nil handle before `Bind` or `Update`.

```go
func LocationSelector(apply func(ctx context.Context, city int)) gox.Comp {
    loc := doors.NewSource(location{})
    country := doors.DeriveSource(loc,
        func(l location) Place { return l.country },
        func(l location, c Place) location { l.country = c; return l },
    )
    return locationSelector{location: loc, country: country, apply: apply}
}
```

## Lifecycle

When a dynamic parent unmounts, all subscriptions (Bind, Effect, Sub), hooks, and Doors inside it are canceled and cleaned up.

Wrap a component in `<>...</>` to force re-initialization on each navigation — the constructor runs fresh, state is re-created. Without the wrapper, the component instance is reused across route switches:

```gox
~(path.Route(
    doors.RouteMatch(func(p Path) bool { return p.Route == Selector }).
        Comp(<>
            ~(LocationSelector(func(ctx context.Context, city int) { ... }))
        </>),
    doors.RouteDefault(WeatherDashboard),
))
```

## Related

- [06-state.md](./06-state.md) — Source, Beam, Bind, Effect, derivation
- [07-door.md](./07-door.md) — Door low-level API (what Bind/Effect use internally)
- [05-routing.md](./05-routing.md) — RouteModel, path models
- [18-storage-auth.md](./18-storage-auth.md) — Session-scoped state
