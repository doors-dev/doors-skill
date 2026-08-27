# Door

`doors.Door` is the **low-level** primitive for dynamic page regions. Update, replace, or remove part of the page without full re-render.

> Most of the time you don't need to use Door directly. Use state-driven rendering instead: `Bind` (rerenders a fragment on value change) or `Effect` (rerenders a dynamic container when any read value changes). See `06-state.md` for those patterns. Reach for Door methods directly only when you need explicit control over the update strategy, or when building higher-level abstractions.

## Type

```go
type Door = door.Door
```

## Rendering

### Proxy (mount with seed content)

```gox
elem (p *Panel) Main() {
    ~>(p.body) <div>
        Initial content
    </div>
}
```
Proxied element becomes the Door container. If the proxy has seed content (`<div>seed</div>`), that becomes the initial content. If the proxy has no content (`<div></div>`) and the Door had stored state from a prior `Inner` call, the stored content renders inside the empty tag. If both seed and stored state are absent, the container is empty.

### Current State (render stored content)

```gox
~(&p.body)
```
Uses the Door's last container or creates its own (`d0-r` tag with `display: contents`).

### Containers

- `~>(door) <tag>...</tag>` — tag becomes container
- `~>(door) <>...</>` — Doors creates its own container
- `~(&door)` — reuses last container

A Door can only be mounted in one place at a time.

## Methods

```go
func (d *Door) Inner(ctx context.Context, content any) <-chan error  // replace children, keep container
func (d *Door) Outer(ctx context.Context, outer any) <-chan error    // replace outer element, keep live handle
func (d *Door) Static(ctx context.Context, content any) <-chan error // replace with static content (no longer live)
func (d *Door) Reload(ctx context.Context) <-chan error              // re-render current content
func (d *Door) Unmount(ctx context.Context) <-chan error             // remove from DOM, keep content
func (d *Door) Freeze(ctx context.Context) <-chan error              // keep markup on page, release server side
```

`Outer` accepts any renderable — element, comp, string, slice — not only `gox.Elem`; a typed-nil `gox.Elem` behaves like `nil` (no panic).

Passing `nil` as content works for all content-taking methods:

| Method | `nil` effect |
|--------|-------------|
| `Inner(ctx, nil)` | Empty the Door, keep it alive |
| `Outer(ctx, nil)` | Mounted placeholder (`d0-r`), no layout effect |
| `Static(ctx, nil)` | Remove without replacement |

### Freeze

`Freeze(ctx)` keeps the Door's current markup on the page but releases everything behind it on the server: hooks, subscriptions, nested Doors; `doors.Go` contexts inside are canceled. Interactive elements stay visible but silently stop working. Unlike `Static`, no content is sent. The Door keeps its stored state and can be mounted again. Made for content that is dynamic only for a while and then final — feed blocks, log/chat entries, streamed output: freeze the finished block, drop the reference, server memory stays flat as the page grows.

### Completion channels

Each mutating method returns `<-chan error` (signatures above); the return value is optional to use:

- success: two `nil` then close — first `nil` = scheduled (render completed), second = applied to the page
- failure: one error then close; `context.Canceled` = superseded by a newer Door operation, unmount, or lifecycle change
- closed with no value = Door not mounted when observed; stored state was still updated (affects future renders)

**Do not wait on the channel during rendering.** Wait in a hook, in `doors.Go`, or in a goroutine with `doors.DetachedContext(ctx)` / `doors.InstanceContext(ctx)` (for work that outlives the fragment).

### doors.Go ordering

`doors.Go(f)` starts `f` only after the render cycle producing the surrounding content completes and is enqueued for delivery — Door updates made inside always land after their host markup. Best-effort like `OnReady`: `f` never runs if the cycle fails or is superseded. Its ctx is `DetachedContext`-equivalent, canceled when the surrounding content is released (replaced, unmounted, or frozen); waiting on completion channels inside `f` is safe.

## Lifecycle

A Door has two sides: stored state (on the Go value) and mounted state (on the page):

1. New Door starts unmounted
2. Methods called before mount store state for later:
   - `Inner` before mount → stores children that will appear
   - `Inner(ctx, nil)` before mount → stores empty Door
   - `Outer` before mount → stores new outer element
   - `Static` before mount → stores static content (no longer a live Door)
   - `Static(ctx, nil)` before mount → stores absent state
   - `Unmount` before mount → keeps content for a later mount
   - `Freeze` before mount → stored state unchanged
3. When rendered, mounts saved state (unless proxied with seed content — `~>(door) <div>seed</div>` overwrites stored state)
4. While mounted, changes sync to DOM

After `Static`, `Freeze`, or `Unmount`, methods still update stored state — they don't auto-remount, but affect future renders if the Door is rendered again.

### Lifecycle Hooks

```go
func OnReady(ctx context.Context, on func(ctx context.Context))  // render cycle producing the current content completed (update enqueued for the client)
func OnSettle(ctx context.Context, on func(ctx context.Context), ops ...func(ctx context.Context)) // current dispatch batch settled
func OnClean(ctx context.Context, f func())                      // current content cleared
func HoldSettle(ctx context.Context) (release func())            // keep the dispatch batch open past handler return
```

- `OnReady` — **best-effort, at most once**: never fires if the render fails or is superseded by a newer Door operation. Fires promptly if the content is already on the page (e.g. in an event handler).
- `OnSettle` — **exactly once**: runs `ops` within the current dispatch batch (in a handler the batch spans the whole handler) and fires `on` once everything the batch started — door updates, beam propagation — is processed and enqueued. Fires even on cancel, render failure, or instance shutdown (the provided ctx reports it). Settling is server-side: updates queued, not browser-acknowledged. Practical uses: a reliable point to collect information gathered during render; controlled batched UI updates — the next batch issued from `on` is guaranteed to land after the previous one.
- `OnClean` — **exactly once** on every teardown path: Door update (`Inner`/`Outer`/`Reload`), removal (`Static`/`Unmount`), freeze (`Freeze`), ancestor re-render, render failure, instance end. No ctx (the registering ctx is already canceled); capture `InstanceContext(ctx)` beforehand if teardown needs Doors calls. On replacement, old content's `OnClean` runs before new content's `OnReady`.
- `HoldSettle` — keeps the current dispatch batch open after the handler returns until `release()` is called: `OnSettle` callbacks, indicators, scopes, and the client `$hook` promise stay pending. Use it to hand work to another goroutine. Call it synchronously in the handler; always call `release` (idempotent, typically deferred in that goroutine — otherwise the batch settles only at instance end). Operations started with the handler ctx join the batch; `DetachedContext` ones don't. Outside a batch, `release` is a no-op.
- Callbacks run inline on the framework goroutine firing the frame (or the calling goroutine when it already fired); `OnReady`/`OnSettle` receive a `DetachedContext`-equivalent ctx. Never block in them.
- Acquire in render code, release in `OnClean`; never tie cleanup to `OnReady`. All panic if ctx is not a Doors ctx.

```gox
~~
sub := hub.Subscribe()
doors.OnClean(ctx, func() { sub.Close() })
~~
```

## Use Cases

| Method | When |
|--------|------|
| `Inner` | Keep container, change children |
| `Outer` | Change root element/attributes |
| `Static` | Region becomes plain rendered content |
| `Reload` | Redraw current content (depends on external state) |
| `Unmount` | Remove now, keep for reuse later |
| `Freeze` | Content went final: keep markup visible, free server resources, remountable |

## Advanced Patterns

### Lazy Loading

Render a placeholder first, replace it with heavy content after the page is visible. The Door is rendered during `Main()`, then `defer` replaces it with static content:

```gox
elem (c chart) Main() {
    ~~
    door := new(doors.Door)
    defer door.Static(ctx, <img src=(c.load())/>)
    ~~
    <div>
        ~(door)
        <div>Loading...</div>
    </div>
}
```

This works because the Door is rendered before the deferred `Static` replaces it. The placeholder shows immediately; the real content replaces it after rendering completes.

### Appending Content

Chain Doors to grow content incrementally. Each append creates a new Door, stores content + next Door into the previous one via `Static`:

```gox
type Append struct {
    door *doors.Door
}

elem (a Append) Main() {
    Content
    ~(a.door)
    <button
        (doors.AClick{
            Scope: new(doors.ScopeBlocking),
            On: func(ctx context.Context, rp doors.RequestPointer) bool {
                a.add(ctx, "new content")
                return false
            },
        })>
        Append
    </button>
}

func (a *Append) add(ctx context.Context, content any) {
    prev := a.door
    next := new(doors.Door)
    a.door = next
    prev.Static(ctx, <>
        ~(content)
        ~(next)
    </>)
}
```

Each call to `add` chains: the old Door becomes static (final content + new Door slot), and the struct field advances to the new Door. Previous content is preserved, new content appends at the end.

No synchronization is needed for `a.door` because calls to the same hook are serialized. But `a.door` is a plain struct field — when mutating plain struct state from multiple hooks or goroutines, you must handle concurrency yourself. `Source`/`Beam` mutations and Door operations are goroutine-safe.

Notes for growing content:

- Appends work before first render too: Door methods on an unmounted Door write stored state, so the chain builds up behind its head and the first render reproduces it whole. The chain is render-once — the server forgets appended items.
- For items that stay dynamic for a while (streamed output, edit-in-place), mount the dynamic part through its own Door and `Freeze` it when final.
- To pace a fast producer, read the completion channel `Static` returns before the next append.
- Inside tag-restricted parents (`<table>`, `<select>`) the generated `d0-r` container is foster-parented out by the browser — give each new door a real tag first: `next.Outer(ctx, <tr></tr>)`.

### Collections of Doors

When state-driven rendering (`Bind`, `Effect`, `Route`) is not enough — for example, appending content incrementally, managing independent regions that freeze/revive, or building abstractions that need explicit control over the DOM lifecycle — store Doors in whatever structure fits (slice, map, custom index) and manage what each displays directly. Each Door can be updated, ended with `Static`, released with `Freeze`, or `Unmount`ed independently.

Pair with explicit state subscriptions (`Sub`, `ReadAndSub`) for maximum control: both give you explicit, imperative control — no implicit reactivity, just direct manipulation of what's on the page.

## Related

- [state.md](./06-state.md) — `Bind`, `Effect` (built on Door)
- [events.md](./09-events.md) — Handler-triggered Door updates
- [components.md](./08-components.md) — Component lifecycle and rendering strategies
