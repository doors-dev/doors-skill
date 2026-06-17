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
func (d *Door) Inner(ctx context.Context, content any)       // replace children, keep container
func (d *Door) Outer(ctx context.Context, outer gox.Elem)    // replace outer element, keep handle
func (d *Door) Static(ctx context.Context, content any)      // replace with static content (no longer live)
func (d *Door) Reload(ctx context.Context)                   // re-render current content
func (d *Door) Unmount(ctx context.Context)                  // remove from DOM, keep content
```

Passing `nil` as content works for all methods:

| Method | `nil` effect |
|--------|-------------|
| `Inner(ctx, nil)` | Empty the Door, keep it alive |
| `Outer(ctx, nil)` | Mounted placeholder (`d0-r`), no layout effect |
| `Static(ctx, nil)` | Remove without replacement |

### X- variants (completion channel)

```go
func (d *Door) XInner(ctx context.Context, content any) <-chan error
func (d *Door) XOuter(ctx context.Context, outer gox.Elem) <-chan error
func (d *Door) XStatic(ctx context.Context, content any) <-chan error
func (d *Door) XReload(ctx context.Context) <-chan error
func (d *Door) XUnmount(ctx context.Context) <-chan error
```

- two `nil` then close = scheduled (render completed), then applied to page
- non-nil error = failed/canceled before finishing
- `context.Canceled` = overwritten by newer operation or unmount
- closed channel with no value = Door not mounted when observed, but internal state was updated (will affect future renders)

**Do not wait on X* during rendering.** Use `doors.Go`, goroutine with `doors.DetachedContext(ctx)`, or `doors.InstanceContext(ctx)`.

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
3. When rendered, mounts saved state (unless proxied with seed content — `~>(door) <div>seed</div>` overwrites stored state)
4. While mounted, changes sync to DOM

After `Static` or `Unmount`, methods still update stored state — they don't auto-remount, but affect future renders if the Door is rendered again.

## Use Cases

| Method | When |
|--------|------|
| `Inner` | Keep container, change children |
| `Outer` | Change root element/attributes |
| `Static` | Region becomes plain rendered content |
| `Reload` | Redraw current content (depends on external state) |
| `Unmount` | Remove now, keep for reuse later |

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

Each call to `add` chains: the old Door becomes static (frozen content + new Door slot), and the struct field advances to the new Door. Previous content is preserved, new content appends at the end.

No synchronization is needed for `a.door` because calls to the same hook are serialized. But `a.door` is a plain struct field — when mutating plain struct state from multiple hooks or goroutines, you must handle concurrency yourself. `Source`/`Beam` mutations and Door operations are goroutine-safe.

### Collections of Doors

When state-driven rendering (`Bind`, `Effect`, `Route`) is not enough — for example, appending content incrementally, managing independent regions that freeze/revive, or building abstractions that need explicit control over the DOM lifecycle — store Doors in whatever structure fits (slice, map, custom index) and manage what each displays directly. Each Door can be updated, frozen with `Static`, or `Unmount`ed independently.

Pair with explicit state subscriptions (`Sub`, `ReadAndSub`) for maximum control: both give you explicit, imperative control — no implicit reactivity, just direct manipulation of what's on the page.

## Related

- [state.md](./06-state.md) — `Bind`, `Effect` (built on Door)
- [events.md](./09-events.md) — Handler-triggered Door updates
- [components.md](./08-components.md) — Component lifecycle and rendering strategies
