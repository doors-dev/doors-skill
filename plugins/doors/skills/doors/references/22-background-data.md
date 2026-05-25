# Background Data

Pushing data from external sources (Kafka, Watermill, WebSocket, polling) into Doors reactive state via background goroutines.

## Which Scope?

| Data is... | Scope | Where to start | Context |
|------------|-------|---------------|---------|
| Consumed by one component | Component | Component constructor or `Main()` | `DetachedContext(ctx)` |
| Consumed by the whole page | Instance | Root component `Main()` | `DetachedContext(ctx)` or `InstanceContext(ctx)` |
| Shared across pages/tabs | Session | App factory via `SessionStore.Init` | `SessionContext(ctx)` |

## Local: Component or Instance

Start the goroutine where the data is consumed. Use `DetachedContext` to get a context that:

- Stays bound to the current dynamic owner (component or instance)
- Is detached from rendering frames (no deadlock)
- Is canceled when the owner unmounts

```go
type Profile struct {
    Name   string
    Avatar string
}

func NewProfileView(poll func(ctx context.Context, onUpdate func(Profile))) gox.Comp {
    profile := doors.NewSourceEqual(Profile{}, func(a, b Profile) bool {
        return a == b
    })
    return profileView{profile: profile, poll: poll}
}

type profileView struct {
    profile doors.Source[Profile]
    poll    func(ctx context.Context, onUpdate func(Profile))
}

elem (f profileView) Main() {
    ~{
        ctx := doors.DetachedContext(ctx)
        go f.poll(ctx, func(p Profile) {
            f.profile.Update(ctx, p)
        })
    }
    ~(f.profile.Bind(f.showProfile))
}

elem (f profileView) showProfile(p Profile) {
    <div>{p.Name}</div>
}
```

### doors.Go helper

`doors.Go` starts a function on a detached context. It renders directly in the template:

```gox
~(doors.Go(func(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        case p := <-ch:
            f.profile.Update(ctx, p)
        }
    }
}))
```

`doors.Go` uses `DetachedContext` internally. The goroutine stops when the owning component unmounts.

### DetachedContext vs InstanceContext

- `DetachedContext` — keeps current dynamic ownership. Use when the goroutine needs to call Door methods (`Inner`, `Outer`) on the same Door it started from.
- `InstanceContext` — switches ownership to the root of the instance. Use when the goroutine should outlive the current dynamic owner but still stop when the page closes.

Both are detached from rendering frames. Neither can be used for `Beam.Read`, `Beam.Sub`, `Beam.Effect`, or `Beam.Bind` — those need a render context.

## Session-Scoped

When background data should be shared across all pages/tabs in a session (e.g., notifications, real-time prices), use `SessionStore.Init` in the app factory. This is the same mechanism as the auth pattern — `Init` ensures one goroutine per session.

### 1. Define a private key and start goroutine in Init

```go
type pricesKey struct{}

app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
    prices := doors.SessionStore(ctx).Init(pricesKey{}, func() any {
        s := doors.NewSource(Prices{})
        sctx := doors.SessionContext(ctx)
        go subscribePrices(sctx, s)
        return s
    }).(doors.Source[Prices])
    return App{prices: prices}
})
```

`Init` runs the function once per session. Subsequent requests in the same session get the existing `Source`. The goroutine is bound to `SessionContext` — it cancels when the session ends.

### 2. Subscribe function

```go
func subscribePrices(ctx context.Context, s doors.Source[Prices]) {
    ch := kafka.Subscribe("prices")
    for {
        select {
        case <-ctx.Done():
            kafka.Unsubscribe(ch)
            return
        case msg := <-ch:
            s.Update(ctx, decodePrices(msg))
        }
    }
}
```

### 3. Consume in components

```gox
type App struct {
    prices doors.Source[Prices]
}

elem (a App) Main() {
    ~(a.prices.Bind(a.showPrices))
}
```

All pages in the session share the same `Source`. When it updates, every bound fragment across every tab re-renders.

### SessionContext API compatibility

`SessionContext` allows mutations but not reads requiring render context:

| ✅ OK | ❌ NOT OK |
|-------|-----------|
| `Source.Update` / `Source.Mutate` | `Source.Read` / `Source.ReadAndSub` |
| `Source.Get` / `Beam.Get` | `Beam.Read` / `Beam.ReadAndSub` |
| Door methods (`Inner`, `Outer`, etc.) | `Beam.Sub` / `Beam.Effect` / `Beam.Bind` |
| `SessionStore` | `InstanceStore` |

## Rules

- Always use a Doors-derived context (`DetachedContext`, `InstanceContext`, `SessionContext`), never `context.Background()`.
- Always handle `ctx.Done()` — the goroutine must stop when the context cancels.
- Do not call `Beam.Read`, `Beam.Sub`, `Beam.Effect`, or `Beam.Bind` from background goroutines. These need a render context.
- `Source.Update` and `Source.Mutate` work from any context. `Source.Get`/`Beam.Get` also work anywhere (returns latest value, no consistency guarantees).
- Door handle methods (`Inner`, `Outer`, `Static`, `Reload`, `Unmount`) work from detached and session contexts.
- For session-scoped state, always use `SessionStore.Init` in the app factory — it guarantees one goroutine per session regardless of how many pages are open.
- Do not start session-scoped goroutines from component `Main()` — they would multiply per page instance.

## Related

- [context.md](./03-context.md) — context types, API compatibility tables, choosing the right context
- [storage-auth.md](./18-storage-auth.md) — `SessionStore.Init` pattern, auth bootstrap
- [state.md](./06-state.md) — Source/Beam API, updates, subscriptions
- [session-instance.md](./19-session-instance.md) — `SessionContext`, `InstanceContext`, lifecycle
