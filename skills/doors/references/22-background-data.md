# Background Data

Pushing data from external sources (Kafka, Watermill, WebSocket, polling) into Doors reactive state via background goroutines — and reacting to state changes from background goroutines via `Sub`/`Watch`.

## Which Scope?

| Data is... | Scope | Where to start | Context |
|------------|-------|---------------|---------|
| Consumed by one component | Component | `Main()` via `doors.Go` or `OnReady` | `DetachedContext(ctx)` |
| Consumed by the whole page | Instance | Root component `Main()` via `doors.Go` or `OnReady` | `DetachedContext(ctx)` or `InstanceContext(ctx)` |
| Shared across pages/tabs | Session | App factory via `SessionStore.Init` | `SessionContext(ctx)` |

## Local: Component or Instance

Start the goroutine where the data is consumed. Register it with `doors.OnReady` so it runs only after the markup it feeds is enqueued for the client; the callback's context is `DetachedContext`-equivalent — it:

- Stays bound to the current dynamic owner (component or instance)
- Is detached from rendering frames (no deadlock)
- Is canceled when the owner's content is cleared (replaced or unmounted)

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
    ~~
    doors.OnReady(ctx, func(ctx context.Context) {
        go f.poll(ctx, func(p Profile) {
            f.profile.Update(ctx, p)
        })
    })
    ~~
    ~(f.profile.Bind(f.showProfile))
}

elem (f profileView) showProfile(p Profile) {
    <div>~(p.Name)</div>
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

`doors.Go` starts `f` only after the render cycle producing the surrounding content completes and is enqueued for delivery, so Door updates made inside always land after their host markup. Best-effort: if the cycle fails or is superseded, `f` never runs (inside `Door.Static` content it belongs to the parent, so a failed static render does not drop it). Its context is equivalent to `DetachedContext` — canceled when the surrounding content is cleared.

From imperative render code, `doors.OnReady(ctx, on)` gives the same timing guarantee: start streaming goroutines inside `on` so they never outrun the markup they target.

### DetachedContext vs InstanceContext

- `DetachedContext` — keeps current dynamic ownership. Use when the goroutine needs to call Door methods (`Inner`, `Outer`) on the same Door it started from.
- `InstanceContext` — switches ownership to the root of the instance. Use when the goroutine should outlive the current dynamic owner but still stop when the page closes.

Both are detached from rendering frames. `Beam.Read`, `Sub`, `ReadAndSub`, and `Watch` work on them; subscriptions are owned by the dynamic owner (`DetachedContext`) or the instance root (`InstanceContext`). Only `Beam.Effect` and `Beam.Bind` belong in render code.

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

### Reacting to state from the background (UI → external)

Background goroutines can consume state, not only produce it: `Sub`, `ReadAndSub`, and `Watch` work on `SessionContext` and other non-instance contexts. Such subscriptions attach directly to the source and end when the callback returns `true` or the context is canceled (session end).

```go
sctx := doors.SessionContext(ctx)
filters.Sub(sctx, func(ctx context.Context, f Filters) bool {
    feed.Resubscribe(f) // adjust the external subscription to follow UI state
    return false
})
```

Use `Watch` when you need to cancel the subscription explicitly — it returns a `context.CancelFunc`.

### SessionContext API compatibility

`SessionContext` carries the session and nothing else — user context values are dropped, and instance-scoped APIs panic:

| ✅ OK | ❌ NOT OK |
|-------|-----------|
| `Source.Update` / `Source.Mutate` | `Beam.Effect` / `Beam.Bind` (render-only) |
| `Beam.Read` / `ReadAndSub` / `Sub` / `Watch` | `InstanceStore` |
| `Source.Get` / `Beam.Get` | `doors.Reload` |
| Door methods (`Inner`, `Outer`, etc.) | instance-scoped helpers (`InstanceID`, `IDNumber`, ...) |
| `SessionStore` | |

## Rules

- Always use a Doors-derived context (`DetachedContext`, `InstanceContext`, `SessionContext`), never `context.Background()`.
- Always handle `ctx.Done()` — the goroutine must stop when the context cancels.
- `Beam.Effect` and `Beam.Bind` are render-only. `Read`, `Sub`, `ReadAndSub`, and `Watch` work from any context; subscriptions made outside an instance end when their context is canceled.
- `Source.Update` and `Source.Mutate` work from any context and return an optional `<-chan error` completion channel. `Source.Get`/`Beam.Get` also work anywhere (latest value, no consistency guarantees).
- Start goroutines that push into freshly rendered content via `doors.Go` or `doors.OnReady` — their updates then land after the host markup.
- Door handle methods (`Inner`, `Outer`, `Static`, `Reload`, `Unmount`) work from detached and session contexts and return an optional `<-chan error`.
- For session-scoped state, always use `SessionStore.Init` in the app factory — it guarantees one goroutine per session regardless of how many pages are open.
- Do not start session-scoped goroutines from component `Main()` — they would multiply per page instance.

## Related

- [context.md](./03-context.md) — context types, API compatibility tables, choosing the right context
- [storage-auth.md](./18-storage-auth.md) — `SessionStore.Init` pattern, auth bootstrap
- [state.md](./06-state.md) — Source/Beam API, updates, subscriptions
- [session-instance.md](./19-session-instance.md) — `SessionContext`, `InstanceContext`, lifecycle
