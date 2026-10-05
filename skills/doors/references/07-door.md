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
```

`Outer` accepts any renderable — element, comp, string, slice — not only `gox.Elem`; a typed-nil `gox.Elem` behaves like `nil` (no panic).

Passing `nil` as content works for all content-taking methods:

| Method | `nil` effect |
|--------|-------------|
| `Inner(ctx, nil)` | Empty the Door, keep it alive |
| `Outer(ctx, nil)` | Mounted placeholder (`d0-r`), no layout effect |
| `Static(ctx, nil)` | Remove without replacement |

### Static

`Static(ctx, content)` replaces the Door with content that is no longer live; the Door is unmounted and can be garbage collected. Static content may mount new Doors of its own — the building block for appending (see Appending Content).

Static content belongs to the Door's parent: hooks, subscriptions, `doors.Go`, and lifecycle callbacks (`OnReady` included) registered while rendering it attach to the parent and live until the parent's content is cleared, even if the static render fails. Calls it makes during render (`doors.Call`) go through the parent too and are sent even if the static render fails. Nothing else stays on the parent, so a chain of `Static` appends keeps server memory flat (see Appending Content).

`Static` issued from a beam subscription renders current state: the content sees a consistent snapshot, which can be newer than the value that triggered the subscription. Pass the value in when the content must match it.

### Once

A Door stores its content until replaced, so a large value passed to `Inner`/`Outer` stays in memory while the Door holds it. `doors.Once(v)` renders `v` on the first render only and drops its reference:

```go
door.Outer(ctx, doors.Once(&UserList{users: users}))
```

Trade-off: a Door rendered again (`Reload`, ancestor re-render, remount) comes back empty. Use for content rendered and then left alone, or replaced on every update. Hooks keep what their handlers capture — a component whose methods serve as handlers stays in memory until its hooks are removed.

### Completion channels

Each mutating method returns `<-chan error` (signatures above); the return value is optional to use:

- success: two `nil` then close — first `nil` = scheduled (render completed), second = applied to the page
- failure: one error then close; a failed render sends its error (see Render errors); `context.Canceled` = superseded by a newer Door operation, unmount, or lifecycle change
- closed with no value = Door not mounted when observed; stored state was still updated (affects future renders)

**Do not wait on the channel during rendering.** Wait in a hook, in `doors.Go`, or in a goroutine with `doors.DetachedContext(ctx)` / `doors.InstanceContext(ctx)` (for work that outlives the fragment).

### doors.Go ordering

`doors.Go(f)` starts `f` only after the render cycle producing the surrounding content completes and is enqueued for delivery — Door updates made inside always land after their host markup. Best-effort like `OnReady`: `f` never runs if the cycle fails or is superseded (inside `Static` content it belongs to the parent, so a failed static render does not drop it). Its ctx is `DetachedContext`-equivalent, canceled when the surrounding content is released (replaced or unmounted); waiting on completion channels inside `f` is safe.

### Render errors

A marginal case: render functions return errors only if you return one yourself, and that is rarely right — render loading failures and missing data as content. When a Door's render fails, nothing is sent to the browser and the error is logged as `door rendering error` with the call site (a render failing because it was superseded is not logged).

- **Door operation** (`Inner`, `Outer`, `Static`, `Reload`): the error goes to its completion channel. The page keeps the previous content, but it no longer responds — its hooks and subscriptions were released when the operation started. The next successful operation replaces it. After a failed `Outer`, `Inner` fails until a new `Outer` succeeds or the parent renders the Door again; recover with a new `Outer`, not `Reload` (once an `Inner` was issued, `Reload` fails too). A failed `Static` still makes the Door static: later operations only update its stored state.
- **Door rendered by its parent** (initial page or parent update): left out of the parent's output. Operations on it fail with a placement error until the parent renders it again.

No error marker reaches the page (the old `Component Error` element is gone): to observe failures, read the operation's channel or the log. `AData` values are encoded and templ components rendered during the render pass, so an `AData` value that fails to encode or a templ error is a render error too.

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

### Lifecycle Hooks

```go
func OnReady(ctx context.Context, on func(ctx context.Context))  // render cycle producing the current content completed (update enqueued for the client)
func OnSettle(ctx context.Context, on func(ctx context.Context), ops ...func(ctx context.Context)) // current dispatch batch settled
func OnClean(ctx context.Context, f func())                      // current content cleared
func HoldSettle(ctx context.Context) (release func())            // keep the dispatch batch open past handler return
```

- `OnReady` — **best-effort, at most once**: never fires if the render fails or is superseded by a newer Door operation. A failed `Static` render is the exception: its content belongs to the parent. Fires promptly if the content is already on the page (e.g. in an event handler).
- `OnSettle` — **exactly once**: runs `ops` within the current dispatch batch (in a handler the batch spans the whole handler) and fires `on` once everything the batch started — door updates, beam propagation — is processed and enqueued. Fires even on cancel, render failure, or instance shutdown (the provided ctx reports it). Settling is server-side: updates queued, not browser-acknowledged. Practical uses: a reliable point to collect information gathered during render; controlled batched UI updates — the next batch issued from `on` is guaranteed to land after the previous one.
- `OnClean` — **exactly once** on every teardown path: Door update (`Inner`/`Outer`/`Reload`), removal (`Static`/`Unmount`), ancestor re-render, render failure (not for `Static` content, which belongs to the parent), instance end. No ctx (the registering ctx is already canceled); capture `InstanceContext(ctx)` beforehand if teardown needs Doors calls. The only ordering guarantee is per piece of content: its `OnClean` runs after its `OnReady` has run or been dropped. The replaced content's `OnClean` is not ordered with the replacing content's render or `OnReady`.
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
| `doors.Once(v)` | Don't keep rendered content in Door memory |
| `Static` chain | Page accumulates items (feeds, logs, chats, streams); server keeps only the growth edge |

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

`Static` content may mount new Doors, which turns `Static` into an append primitive (the docs' Growing Content recipe):

- **Edge handoff** — keep one Door as the growth edge; to append, replace the edge with the item plus a fresh edge. The page grows without bound while the server keeps one live Door per chain, so server memory stays flat.
- **Pre-mount buffering** — Door methods on an unmounted Door write stored state, so appends may arrive before the feed renders: the chain builds up behind its head Door and the first render reproduces it whole.
- **Render-once** — appended items go to the page and are forgotten. Consuming the seed drops the last reference to the chain, so a later render starts a fresh one; when the feed must survive an ancestor re-render, render past items from your data source.

```gox
type Feed struct {
    mu   sync.Mutex
    seed *doors.Door
    tail *doors.Door
}

func (f *Feed) Append(ctx context.Context, item gox.Elem) {
    f.mu.Lock()
    defer f.mu.Unlock()
    // append before the first render: seed a head door that holds the chain until it mounts
    if f.tail == nil {
        f.seed = new(doors.Door)
        f.tail = f.seed
    }
    // replace the edge with the item plus a fresh edge
    next := new(doors.Door)
    f.tail.Static(ctx, <>
        ~(item)
        ~(next)
    </>)
    f.tail = next
}

elem (f *Feed) Main() {
    ~~
    f.mu.Lock()
    defer f.mu.Unlock()
    // consume the seed: the chain renders once, then the server forgets it
    head := f.seed
    f.seed = nil
    if head == nil {
        head = new(doors.Door)
        f.tail = head
    }
    ~~
    <section class="feed">~(head)</section>
}
```

One mutex guards `seed` and `tail` across both paths: Door methods are goroutine-safe, but the fields tracking the chain are plain struct state and yours to synchronize. Holding the lock across the render body is fine — a Door's content render is scheduled on the runtime, not performed inline.

Notes for growing content:

- The edge's position sets the direction: edge after the item grows down (append), edge before it grows up (prepend).
- For items that stay dynamic for a while (streamed output, edit-in-place), mount the dynamic part through its own Door and call `Static` on that Door with the final content when done. Keep the final content free of hooks and subscriptions: static content registers them on the parent, where they live as long as the feed does.
- To pace a fast producer, read the completion channel `Static` returns before the next append.
- Inside tag-restricted parents (`<table>`, `<select>`) the generated `d0-r` container is foster-parented out by the browser — give each new edge a real tag first: `next.Outer(ctx, <tr></tr>)`.

### Collections of Doors

When state-driven rendering (`Bind`, `Effect`, `Route`) is not enough — for example, appending content incrementally, managing independent regions that come and go, or building abstractions that need explicit control over the DOM lifecycle — store Doors in whatever structure fits (slice, map, custom index) and manage what each displays directly. Each Door can be updated, ended with `Static`, or `Unmount`ed independently.

Pair with explicit state subscriptions (`Sub`, `ReadAndSub`) for maximum control: both give you explicit, imperative control — no implicit reactivity, just direct manipulation of what's on the page.

## Related

- [state.md](./06-state.md) — `Bind`, `Effect` (built on Door)
- [events.md](./09-events.md) — Handler-triggered Door updates
- [components.md](./08-components.md) — Component lifecycle and rendering strategies
