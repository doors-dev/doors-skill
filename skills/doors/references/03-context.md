# Context

The implicit `ctx` in GoX templates and handler callbacks covers 99% of cases. Derived contexts (`SessionContext`, `InstanceContext`, `DetachedContext`) are for manually spawned goroutines — a less common workflow.

Doors uses multiple context layers. Using the wrong one for an API call causes panics or undefined behavior.

## Implicit `ctx` in GoX Templates

Inside `elem` blocks and `~~ ... ~~` code blocks, a `ctx context.Context` variable is **automatically in scope**. It is the Doors runtime context — same as what you receive in handlers. You never need to declare it, receive it as a parameter, or pass it from outside.

```gox
elem (a App) Main() {
    ~~
    // ctx is available here without any declaration
    loc := doors.Router(ctx)         // works
    val, _ := someBeam.Read(ctx)     // works
    auth.Update(ctx, true)            // works
    ~~
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
- **Implicitly: inside `elem` blocks and `~~ ... ~~` code blocks** (see above)

This context carries the current Door, instance, and session. **Always use it for Doors APIs** unless explicitly documented otherwise.

## HTTP Request Context (`r.Context()`)

Available through `RequestEvent.Context()`, `Request.Context()`, etc. This is the standard `*http.Request.Context()`.

**Use for:** HTTP-level operations, timeouts, cancellation tied to the HTTP request.

**Do NOT use for** instance-level Doors APIs (hooks, links, `Router`, `Call`). It carries session-level values only.

## Propagating User Values: `doors.Ctx`

```go
func Ctx(ctx context.Context) gox.Proxy
```

Renders the following element with the **values** of `ctx` — propagates user `context.WithValue` through the render subtree. Values are visible in nested renders, event handlers, and later door updates of that subtree. Cancellation, deadlines, and Doors ownership stay with the enclosing render.

```gox
~>(doors.Ctx(context.WithValue(ctx, themeKey{}, "dark"))) <>
    // subtree sees ctx.Value(themeKey{})
</>
```

Value survival across derived contexts: `InstanceContext` and `DetachedContext` keep user values; `SessionContext` drops them.

## Predicates & Utilities

```go
func HasSession(ctx context.Context) bool   // ctx carries a Doors session (SessionID, SessionStore, ... accept it)
func HasInstance(ctx context.Context) bool  // ctx belongs to a render/handler (instance APIs accept it); implies HasSession
func IsDocument(ctx context.Context) bool   // ctx renders into the HTML of the page response
func Logger(ctx context.Context) *slog.Logger // configured Doors logger; slog.Default fallback; any ctx, never panics
func IDNumber(ctx context.Context) uint64   // instance-unique, non-sequential number; needs instance ctx
```

`HasSession`/`HasInstance`/`IsDocument` never panic. Use `HasSession`/`HasInstance` to check which API level a context supports before calling.

`IsDocument(ctx)` is `true` while rendering the HTML page response (the page the browser loads), and `false` for anything rendered later. Use it to render slow content inline on page load and, on later updates, show a placeholder and load the content with `doors.DeferredInner` (loader pattern in [door.md](./07-door.md)).

**Details:** `true` in the initial page render and every Door placed during it. `false` in every update (even one rendered before the response is sent), in handlers and callbacks, and with `DetachedContext` or `InstanceContext`. Contexts derived with the `context` package keep the value.

## Derived Contexts

### SessionContext

```go
func SessionContext(ctx context.Context) context.Context
```

Returns a context canceled when the current **session** ends. Carries the session and nothing else: user ctx values are dropped; not tied to any instance or dynamic owner.

**OK with SessionContext:**

- `Source.Update` / `Source.Mutate`
- `Beam.Read` / `ReadAndSub` / `Sub` / `Watch` — subscription attaches to the source, ends when the session ends
- `Source.Get` / `Beam.Get` (latest value)
- Door methods (`Inner`, `Outer`, `Static`, `DeferredInner`, `DeferredOuter`, `DeferredStatic`, `Reload`, `Unmount`)
- Session-scoped goroutines/helpers
- `doors.Session*` APIs (`SessionStore`, `SessionExpire`, `SessionEnd`, `SessionID`, `SessionLastSeen`)
- `doors.Logger`

**NOT OK with SessionContext (panics):**

- `doors.Instance*` APIs (`InstanceStore`, `InstanceEnd`, `InstanceID`, `InstanceLastSeen`), `IDNumber`
- Top-level `doors.Reload`, `doors.DeferredInner` / `DeferredOuter` / `DeferredStatic`, `Router`, `Call`, `A(ctx, ...)`

`Beam.Effect` does not panic but returns `false` — it needs an instance runtime.

Use when work should outlive a single page instance but stop when the session ends.

The app factory `ctx` (`doors.NewApp(func(ctx, r)...)`) is a full runtime context — all APIs work. The request context in middleware (`app.Use(...)`) and `r.Context()` in event handlers carry session-level values (same OK/NOT OK rules as `SessionContext`); the session itself is lazy — first session-scoped call creates it.

### InstanceContext

```go
func InstanceContext(ctx context.Context) context.Context
```

Returns a context detached from the current dynamic owner, bounded by the current **instance** lifetime. Keeps the values of `ctx`; switches Doors ownership to the root of the current instance, so subscriptions and hooks made with it survive rerenders of the caller. Detached: completion channels deliver results on it (see Completion channels).

Use for:
- Goroutines that should outlive the current dynamic owner (e.g., a Door) but stop when the page closes
- Work safe to continue after the owning component unmounts

### DetachedContext

```go
func DetachedContext(ctx context.Context) context.Context
```

Returns a detached context bounded by the lifetime of `ctx`. Keeps the values of `ctx` and the current Doors ownership (canceled when the owning content is cleared). Operations made with it are delivered on their own: they do not join a handler's updates, batch, or indicator.

Use for:
- Goroutines of your own that keep the current dynamic ownership (call Door methods on the same Door they started from)
- Waiting on completion channels — only a detached ctx delivers results (see Completion channels)
- Work that should stop when the owning component unmounts

Operations made with a detached context (`DetachedContext`, `InstanceContext`) are not part of the current handler's work: not its batch, its indicator, or `OnSettle`. **Wait on their channels only in goroutines of your own**, never during rendering, in a handler, or in a subscription: that can block the page.

### Completion channels

Door methods (`Inner`, `Outer`, `Static`, `Deferred*`, `Reload`, `Unmount`), top-level `doors.Deferred*`/`doors.Reload`, and `doors.Call` return `<-chan error`. What it delivers depends only on whether `ctx` is detached:

- First value, when the call is scheduled: `nil`, or an error if it failed before scheduling (render failed; action could not be built; canceled or superseded by a newer operation = `context.Canceled`). Door not mounted = closed with no value.
- Closed without a further value = accepted, outcome not reported (Door not mounted yet, or ctx not detached). Every failure arrives as an error value.
- Detached ctx: a second value follows — Door op: `nil` = applied to the page, or an error; `doors.Call`: `nil` = browser answered (an `Into` destination is written before it), or an error (client failed, result not decodable); `context.Canceled` = canceled after scheduling. Then close.
- Any other ctx: the channel closes right after the first value. No "applied", no result; an `Into` destination stays unwritten, and the closed channel is the only signal (no error).
- Batches (`Batch: true`, `OnBatch`) do not affect the channel.

Detached ctx: `DetachedContext(ctx)`, `InstanceContext(ctx)`, the ctx of `doors.Go`, the ctx of `OnReady` and `OnBatch` callbacks (`on`), and anything derived from them with the `context` package (`WithTimeout`, `WithCancel`, ...).

NOT detached: handler ctx (event/form/hook, also when used later from a goroutine), render ctx, beam subscription ctx, the ctx of `OnSettle` callbacks (`on`), and the ctx of `OnSettle`/`OnBatch` `ops` (even when the call was made with a detached ctx).

Pattern — read both values, in a goroutine of your own, on a detached ctx:

```go
go func(ctx context.Context) {
	var dst T
	ch := doors.Call(ctx, action.Into(&dst))
	<-ch // scheduled
	if err, ok := <-ch; ok && err == nil {
		use(dst)
	}
}(doors.DetachedContext(ctx))
```

## API Context Requirements

### Source / Beam

| Method | Required context |
|--------|-----------------|
| `Read(ctx)` | Any Doors context (instance, session, or background) |
| `Sub(ctx, fn)` | Any Doors context; see subscription lifetime below |
| `ReadAndSub(ctx, fn)` | Any Doors context; see subscription lifetime below |
| `Watch(ctx, w)` | Any Doors context; see subscription lifetime below |
| `Effect(ctx)` | Instance render context (returns `false` otherwise) |
| `Bind(fn)` | (internally uses render context) |
| `Get()` | No context needed |
| `Update(ctx, v)` | Any context |
| `Mutate(ctx, fn)` | Any context |
| `Route(routes...)` | Render context (via cursor) |
| `RouteBeam(routes...)` | Render context (via cursor) |

Subscription lifetime: registered from instance content, a subscription ends when that content is cleared. Registered from outside an instance (`SessionContext`, background context), it binds directly to the source and ends when the context is canceled — a never-canceled context means a never-ending subscription.

### Door

| Method | Required context |
|--------|-----------------|
| `Inner` / `Outer` / `Static` / `DeferredInner` / `DeferredOuter` / `DeferredStatic` / `Reload` / `Unmount` | Any Doors context — the handle carries the mounted node |

Door handle methods run with `SessionContext`, instance render context, `DetachedContext`, or `InstanceContext`. The top-level `doors.Reload(ctx)` and `doors.DeferredInner` / `DeferredOuter` / `DeferredStatic(ctx, content)` helpers are different: they act on the closest dynamic parent of `ctx`, so they need an instance core and dynamic owner.

### Session / Instance Control

| Function | Required context |
|----------|-----------------|
| `SessionStore(ctx)` | Session value in context |
| `InstanceStore(ctx)` | Instance core in context (NOT SessionContext) |
| `SessionExpire(ctx, d)` | Session value in context |
| `SessionEnd(ctx)` | Session value in context |
| `InstanceEnd(ctx)` | Instance core in context |
| `Reload(ctx)` | Instance core, dynamic owner (NOT SessionContext) |
| `SessionID(ctx)` | Session value in context |
| `InstanceID(ctx)` | Instance core in context |
| `IDNumber(ctx)` | Instance core in context |
| `HasSession(ctx)` / `HasInstance(ctx)` / `IsDocument(ctx)` | Any context (predicates, never panic) |
| `Logger(ctx)` | Any context (falls back to `slog.Default`) |
| `Router(ctx)` | Instance core in context |
| `Call(ctx, action)` | Instance core + current Door (NOT SessionContext) |

### Other

| Function | Required context |
|----------|-----------------|
| `Go(f)` | Render context (f gets a detached ctx, see Completion channels) |
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
├─ Waiting on completion channels (Inner, Call, etc.) → a goroutine of your own with DetachedContext(ctx) or InstanceContext(ctx); only a detached ctx delivers the result — read two values
│  (NEVER during render or in beam subscriptions; in most cases ignore the channel)
│
├─ Passing custom values to a render subtree → ~>(doors.Ctx(context.WithValue(ctx, k, v))) ...
│
├─ Need HTTP request context → r.Context()
│
└─ Session-scoped storage/state mutations from any instance → SessionContext(ctx)
```

## Common Mistakes

1. **Using `context.Background()` for session/instance APIs** — panics. Beam reads/subs accept it, but a subscription on a never-canceled context never ends.
2. **Using `SessionContext` for top-level `doors.Reload` or `doors.DeferredInner` / `DeferredOuter` / `DeferredStatic`** — panics. SessionContext has no dynamic owner.
3. **Expecting a `Beam.Sub` made with `SessionContext` to end on unmount** — it lives until the session ends (or the context is canceled). Pick the context for the lifetime you want.
4. **Using `SessionContext` for `Call`, `Router`, `A(ctx, ...)`, or `InstanceStore`** — these need an instance core.
5. **Waiting on completion channels during render or in beam subscriptions** — deadlock or undefined behavior; a non-detached ctx never delivers a result anyway (channel closes after the scheduled value, `Into` dst unwritten). Ignore the channel, or wait for the second value in a goroutine of your own with `DetachedContext(ctx)` / in `doors.Go`.
6. **Using HTTP request context for instance-level Doors APIs** — panics. `r.Context()` carries session-level values, not instance-level. Just use the `ctx` provided directly.
7. **Requesting Doors actions from an already-canceled context** (typically one kept by a goroutine that outlived its owner) — logs the warning `requested action from a canceled context` with `action` and `caller` attributes. `caller` is the file:line of the first frame outside Doors, with generated templates resolved to their `.gox` source — start debugging there. Use `InstanceContext(ctx)` or `SessionContext(ctx)` for long-running goroutines and awaited operations.
8. **Reading one value from a completion channel and using the `Into` destination** — the first value only means scheduled. Read the second value, on a detached ctx.

## Related

- [state.md](./06-state.md) — Source/Beam API
- [door.md](./07-door.md) — Door methods
- [session-instance.md](./19-session-instance.md) — Session/instance lifecycle
- [storage-auth.md](./18-storage-auth.md) — Session/instance store
- [background-data.md](./22-background-data.md) — Background goroutine patterns
