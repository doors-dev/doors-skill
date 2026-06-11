# Context

The implicit `ctx` in GoX templates and handler callbacks covers 99% of cases. Derived contexts (`SessionContext`, `InstanceContext`, `DetachedContext`) are for manually spawned goroutines — a less common workflow.

Doors uses multiple context layers. Using the wrong one for an API call causes panics or undefined behavior.

## Implicit `ctx` in GoX Templates

Inside `elem` blocks and `~{ ... }` code blocks, a `ctx context.Context` variable is **automatically in scope**. It is the Doors runtime context — same as what you receive in handlers. You never need to declare it, receive it as a parameter, or pass it from outside.

```gox
elem (a App) Main() {
    ~{
        // ctx is available here without any declaration
        loc := doors.Router(ctx)         // works
        val, _ := someBeam.Read(ctx)     // works
        auth.Update(ctx, true)            // works
    }
    <button (doors.AClick{
        On: func(ctx context.Context, r doors.RequestPointer) bool {
            // Inside handler callbacks, the parameter ctx shadows the outer one.
            // Always use the handler's ctx parameter for Doors APIs:
            door.Inner(ctx, "updated")
            return false
        },
    })>Click</button>
}
```

> Inside handler callbacks (`AClick{On: func(ctx, r)...}`, `ASubmit{On: func(ctx, r)...}`), the parameter `ctx` shadows the outer template `ctx`. Use the parameter `ctx` — it's the correct one for the handler's scope.

## The Doors Runtime Context

This is the `ctx` passed to you in:
- Event/hook handlers: `On: func(ctx context.Context, ...) bool`
- Page factory: `doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp { ... })`
- Subscriptions: `beam.Sub(ctx, func(ctx context.Context, v T) bool { ... })`
- **Implicitly: inside `elem` blocks and `~{ ... }` code blocks** (see above)

This context carries the current Door, instance, and session. **Always use it for Doors APIs** unless explicitly documented otherwise.

## HTTP Request Context (`r.Context()`)

Available through `RequestEvent.Context()`, `Request.Context()`, etc. This is the standard `*http.Request.Context()`.

**Use for:** HTTP-level operations, timeouts, cancellation tied to the HTTP request.

**Do NOT use for** any Doors API (reads, updates, hooks, links, session/instance control).

## Derived Contexts

### SessionContext

```go
func SessionContext(ctx context.Context) context.Context
```

Returns a context canceled when the current **session** ends. Carries the current session value.

**OK with SessionContext:**

- `Source.Update` / `Source.Mutate`
- `Source.Get` / `Beam.Get` (latest value)
- Door methods (`Inner`, `Outer`, `Static`, `Reload`, `Unmount`)
- Session-scoped goroutines/helpers
- `doors.Session*` APIs (`SessionStore`, `SessionExpire`, `SessionEnd`, `SessionId`)

**NOT OK with SessionContext:**

- `Source.Read` / `Source.ReadAndSub`
- `Beam.Read` / `Beam.ReadAndSub`
- `Beam.Sub` / `Beam.Watch`
- `Beam.Effect` / `Beam.Bind`
- `doors.Instance*` APIs (`InstanceStore`, `InstanceEnd`, `InstanceId`)
- Top-level `doors.Reload`, `Router`, `Call`, `XCall`, `A(ctx, ...)`

Not tied to the current instance or dynamic owner. Use when work should outlive a single page instance but stop when the session ends.

The app factory `ctx` (`doors.NewApp(func(ctx, r)...)`) is a full runtime context — all APIs work. The request context in middleware (`app.Use(...)`) and `r.Context()` in event handlers carry session-level values (same OK/NOT OK rules as `SessionContext`).

### InstanceContext

```go
func InstanceContext(ctx context.Context) context.Context
```

Returns a context detached from the current dynamic owner, bounded by the current **instance** lifetime. Switches Doors ownership to the root of the current instance.

Use for:
- Goroutines that should outlive the current dynamic owner (e.g., a Door) but stop when the page closes
- Work safe to continue after the owning component unmounts

### DetachedContext

```go
func DetachedContext(ctx context.Context) context.Context
```

Returns a context detached from the current render frame, bounded by the current context lifetime. Keeps current Doors ownership.

Use for:
- Goroutines that should keep the current dynamic ownership (e.g., wait on `X*` methods from the same Door)
- Work that should stop when the owning component unmounts

## API Context Requirements

### Source / Beam

| Method | Required context |
|--------|-----------------|
| `Read(ctx)` | Instance render context |
| `ReadAndSub(ctx, fn)` | Instance render context |
| `Sub(ctx, fn)` | Instance render context |
| `Effect(ctx)` | Instance render context |
| `Watch(ctx, w)` | Instance render context |
| `Bind(fn)` | (internally uses render context) |
| `Get()` | Any context (no context needed) |
| `Update(ctx, v)` | Any context |
| `Mutate(ctx, fn)` | Any context |
| `Route(routes...)` | Render context (via cursor) |
| `RouteBeam(routes...)` | Render context (via cursor) |

### Door

| Method | Required context |
|--------|-----------------|
| `Inner(ctx, v)` | Core context (instance) |
| `Outer(ctx, v)` | Core context (instance) |
| `Static(ctx, v)` | Core context (instance) |
| `Reload(ctx)` | Core context (instance) |
| `Unmount(ctx)` | Core context (instance) |

Door handle methods can run with `SessionContext`, instance render context, `DetachedContext`, or `InstanceContext`; the Door handle carries the mounted node. The top-level `doors.Reload(ctx)` helper is different: it needs an instance core and dynamic owner.

### Session / Instance Control

| Function | Required context |
|----------|-----------------|
| `SessionStore(ctx)` | Session value in context |
| `InstanceStore(ctx)` | Instance core in context (NOT SessionContext) |
| `SessionExpire(ctx, d)` | Session value in context |
| `SessionEnd(ctx)` | Session value in context |
| `InstanceEnd(ctx)` | Instance core in context |
| `Reload(ctx)` | Instance core, dynamic owner (NOT SessionContext) |
| `SessionId(ctx)` | Session value in context |
| `InstanceId(ctx)` | Instance core in context |
| `Router(ctx)` | Instance core in context |
| `Call(ctx, action)` | Instance core + current Door (NOT SessionContext) |
| `XCall[T](ctx, action)` | Instance core + current Door (NOT SessionContext) |

### Other

| Function | Required context |
|----------|-----------------|
| `Go(f)` | Render context (uses `DetachedContext` internally) |
| `Parallel()` | Render context (uses internally) |
| `Status(code)` | Render context (cursor context) |
| `A(ctx, attrs...)` | Render context |

## Choosing the Right Context (Flowchart)

```
Starting point: handler/render ctx
│
├─ Calling Doors APIs (reads, hooks, links) → use the ctx directly
│
├─ Starting a goroutine that should:
│  ├─ Stop when this component unmounts → DetachedContext(ctx) or `~(doors.Go(func(ctx){...}))`
│  ├─ Stop when this page instance ends → InstanceContext(ctx)
│  └─ Stop when the session ends → SessionContext(ctx)
│
├─ Waiting on X* (XUpdate, XInner, etc.) → DetachedContext(ctx) or InstanceContext(ctx)
│  (NEVER during rendering)
│
├─ Need HTTP request context → r.Context()
│
└─ Session-scoped storage/state mutations from any instance → SessionContext(ctx)
```

## Common Mistakes

1. **Using `context.Background()` for Doors APIs** — panics most of the time. Always use the provided `ctx`.
2. **Using `SessionContext` for `Reload`** — panics. SessionContext has no dynamic owner.
3. **Using `SessionContext` for `Beam.Read/Sub`** — these need instance render context.
4. **Using `SessionContext` for `Call`/`XCall`, `Router`, `A(ctx, ...)`, or `InstanceStore`** — these need an instance core.
5. **Waiting on `X*` channels during rendering** — deadlock or undefined behavior. Defer to `Go` or goroutine.
6. **Using HTTP request context for Doors APIs** — panics. `r.Context()` carries session-level values, not instance-level. Just use the `ctx` provided directly.

## Related

- [state.md](./06-state.md) — Source/Beam API
- [door.md](./07-door.md) — Door methods
- [session-instance.md](./19-session-instance.md) — Session/instance lifecycle
- [storage-auth.md](./18-storage-auth.md) — Session/instance store
- [background-data.md](./22-background-data.md) — Background goroutine patterns
