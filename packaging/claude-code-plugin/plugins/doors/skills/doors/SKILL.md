---
name: doors
description: Always use this skill whenever creating, editing, reviewing, debugging, or extending any Doors project, even for small changes. Do not attempt Doors-specific APIs from memory. Always read the bundled Doors-specific GoX reference first. Covers Doors app structure, routing, reactive state, events/hooks, doors, components, navigation, resources, JavaScript, styles, auth, sessions, background data, configuration, GoX, and framework-specific conventions.
license: Apache-2.0
metadata:
  version: "0.6.0"
  language: go
---

# Doors

Doors is a Go framework for building server-side interactive web applications.

Use this skill as the entry point for Doors-specific work. Keep this file as an operating guide and reference router; load detailed API facts from `references/` only when the task needs them.

## Boundary With GoX

Doors apps use GoX templates for almost all rendered UI, so always load the bundled Doors-specific GoX reference before applying Doors-specific guidance.

Read `references/00-gox.md` first for every Doors task, including reviews. This is non-optional; do not answer or edit from GoX memory.

## First Pass Workflow
Before editing a Doors project:

1. Read `references/00-gox.md`.
2. Inspect the existing project structure and conventions; audit current Doors code for routing, state, lifecycle, auth, event, and resource best-practice issues before editing.
3. Check `go.mod` for `github.com/doors-dev/doors`. Run `go get -u github.com/doors-dev/doors@latest` and `go mod tidy` to ensure the project is on the latest Doors version before making changes.
4. Identify the smallest Doors domain involved: app setup, routing, state, components, events, doors, resources, JavaScript, styles, auth, sessions, background data, or configuration.
5. Read matching `references/` files from the map below; `./docs` and code fact-check them, not replace them.
6. Prefer local edits that fit existing routing, state, styling, and auth patterns.
7. When browser/runtime behavior is unclear and no reliable browser controller is available, use a short Rod check or temporary Go test to inspect the real page. Convert it into a committed e2e test when it verifies user-facing behavior or prevents a regression; delete it when it was only exploratory. Do not use Rod for pure logic that ordinary Go tests cover.
8. Run or suggest the appropriate formatting, generation, and test commands for the change.

Ask the user only for product requirements that cannot be inferred from the code, such as unknown URL shape, ambiguous app section, missing data fields, permissions policy, destructive behavior, or deployment settings.

## Core Mental Model
- Each interactive page is a live server-side instance. There is no virtual DOM.
- Two ways to update a page after the first render. Data-driven covers most of an app: a part shows a piece of data (URL, UI state, user status and settings, live metrics/progress/presence) and its content is swapped when the data changes; handlers change state, each part shows what follows from it, and the page always matches the state. Explicit is an operation, not a new value: append, prepend, insert, remove, for virtual/managed lists, growing content (chats, logs, streamed text), and real-time loops; it gives precise control at the cost of more code, since you track what is on the page and keep it in step yourself.
- Components are static by default: `Main()` renders once and stays. Updates are targeted — only fragments triggered by `Bind`/`Effect`, `Sub` callbacks, or direct Door method calls (`Inner`, `Outer`, `Static`, `Reload`, `Deferred*`) from handlers and Sub callbacks re-render. The rest of the tree is untouched.
- State derivation replaces virtual DOM diffing. For all reactive state, use a ladder: branch key owned at that level (often derived), narrower branches, then field/param/query binds only in consuming fragments.
- `Route` swaps only when the matched branch changes (a `RouteBind` leaf rerenders on value change); `Bind`/`Effect` rerender on subscribed value changes, so derive before binding.
- A hook is a server HTTP handler created during render. It lives as long as the Door that encloses it and answers only the session that rendered it. Event handlers, private resources, and custom endpoints (`NewHook`) are all hooks.
- Lifecycle hooks tie work to render delivery: `OnReady` (content enqueued for the client), `OnClean` (content cleared), `OnSettle` (everything the handler started is queued for delivery), `OnBatch` (a group of updates applied in the browser at once), `HoldSettle` (keep indicators, scopes, and the `$hook` promise pending until released).
- A session is shared across browser pages/tabs. An instance is one live page with its own render tree, handlers, subscriptions, and lifecycle. Sessions are created lazily on first actual touch of a session API.

### Concurrency

- Calls to the same hook run one at a time by default, in order of arrival (`doors.RaceSerial`). Different hooks can run in parallel. The `Race` field on any event attr or hook changes that: `doors.RaceParallel` runs its calls concurrently, `doors.RaceStrict` runs one at a time and cancels calls that arrive out of order. Resource hooks (`NewHook`, script/style sources) are always concurrent. `Batch`, next to `Race`, makes the browser apply a handler's updates together.
- Scopes prevent UI artifacts from parallel hooks (e.g. blocking a related hook while another is in progress). Scopes are a client-side scheduling hint for UX, not a concurrency guarantee — do not rely on them for data safety.
- When working with state beyond `doors.Source`/`doors.Beam` (plain struct fields, slices, maps, external caches), you must handle concurrency yourself. `Source`/`Beam` mutations are safe to call from any context; plain Go state is not.
- Mutating operations — Door methods, `doors.Reload`, `doors.DeferredInner`/`DeferredOuter`/`DeferredStatic`, `Source.Update`/`Mutate`, `doors.Call` — return a `<-chan error` completion channel. Ignore it; see Rendering.
- Door content rendering and state propagation run in parallel across independent subtrees, but are coordinated so a render cycle sees one coherent view of all sources and derived beams.

Key primitives:

| Primitive | Purpose |
|-----------|---------|
| `Source[T]` | Writable reactive value |
| `Beam[T]` | Read-only derived or observed value |
| `Door` | Dynamic DOM placeholder for explicit partial updates |
| `Route*` | State-based branching between views |
| Hook attrs (`AClick`, `AInput`, `ASubmit`, etc.) | Server-bound DOM events |
| `Setter` / `Emitter` | Stateless element handles: set attributes on / dispatch synthetic DOM events to attached live elements |
| `OnReady` / `OnSettle` / `OnBatch` / `OnClean` / `HoldSettle` | Lifecycle hooks tied to render delivery and update application |

## Reference Map
After `references/00-gox.md`, read remaining references by task, not all at once.

| Task | Read |
|------|------|
| Always read before any Doors work | `references/00-gox.md` |
| Create a project, inspect starter layout, or add static files | `references/01-get-started.md`, `references/04-app.md`, `references/21-configuration.md` |
| Work with app creation, middleware, mounting, static dirs, or resources at fixed paths | `references/04-app.md` |
| Choose the right context, start goroutines, wait on a completion channel (only in a goroutine of your own), propagate user context values (`doors.Ctx`), or handle detached work | `references/03-context.md` |
| Define/edit routes, path models, route variants, params, query, or fallbacks | `references/05-routing.md`, `references/10-navigation.md` |
| Work with `Source`, `Beam`, `Bind`, `Effect`, `Sub`, derived state, or consistency | `references/06-state.md` |
| Update part of a page explicitly without full re-render | `references/07-door.md`, `references/06-state.md` |
| Keep small per-tab UI state across reloads without putting it in the URL (`TabState`) | `references/06-state.md` |
| Show a placeholder while slow content renders (skeleton, loader in a `Bind` or route, `doors.IsDocument` for the page response) — deferred ops | `references/07-door.md` |
| `Bind`/`Effect` not enough — appending content, making finished content static, dropping rendered content from memory (`Once`), collections of dynamic regions, or other patterns needing low-level Door control | `references/07-door.md` |
| A Door update or page render fails (`door rendering error` in the log, content missing or stale) | `references/07-door.md` |
| Run code when content is delivered, cleared, queued for delivery, or applied in the browser (`OnReady`, `OnClean`, `OnSettle`, `OnBatch`), or keep indication pending past the handler (`HoldSettle`) | `references/07-door.md`, `references/12-indication.md` |
| Build a reactive component or choose `Bind` vs `Effect` | `references/08-components.md` |
| Add click/input/change/submit/key/focus handlers or forms, choose how overlapping calls are handled (`Race`), or apply a handler's updates together (`Batch`) | `references/09-events.md`, `references/11-scopes.md`, `references/12-indication.md`, `references/13-actions.md` |
| Add navigation links (batched by default), active links, or programmatic navigation | `references/10-navigation.md`, `references/12-indication.md` |
| Add loading/pending feedback during requests (indicators, CSS classes, attributes) | `references/12-indication.md` |
| Control request scheduling: prevent double-clicks, rate-limit, debounce, queue, cancel stale | `references/11-scopes.md` |
| Run browser-side actions before/after/on-error, emit JS events, scroll, read the client clock, or hard navigate | `references/13-actions.md` |
| Serve images, downloads, embedded files, or external URLs | `references/14-resources.md` |
| Give browser code its own HTTP endpoint (island API, `EventSource`, `WebSocket`, third-party widget) with `NewHook` | `references/14-resources.md` (Custom Endpoints), `references/15-javascript.md` |
| Add inline scripts, managed scripts, JS modules, Go-to-JS data, or JS-to-Go hooks | `references/15-javascript.md` |
| Add stylesheets, Tailwind classes, inline styles, or class composition | `references/16-styles.md` |
| Element handles: sync attributes across elements (`Setter`) or dispatch synthetic DOM events from the server (`Emitter`) | `references/17-element-handles.md`, `references/09-events.md`, `references/13-actions.md` |
| Add login/logout/auth, OAuth/PKCE flows, or session/instance storage | `references/18-storage-auth.md`, `references/19-session-instance.md`, `references/06-state.md` |
| Control session or instance lifetime | `references/19-session-instance.md` |
| Set page title, meta tags, or initial HTTP status | `references/20-head-status.md` |
| Configure CSP, timeouts, esbuild, server ID, error pages, HEAD handling, or session tracking | `references/21-configuration.md` |
| Observe or transform emitted HTML (`WithPrinter` middleware) | `references/21-configuration.md` |
| Push data from background sources such as polling, Kafka, or Watermill into reactive state | `references/22-background-data.md`, `references/03-context.md` |
| Test a Doors app or design an app-level e2e test harness | `references/23-testing.md` |

## Interaction Defaults

Read `09-events`, `11-scopes`, `12-indication`, and `13-actions` before changing interactive elements. Use Doors event attrs for normal browser events, scopes for request scheduling, indication for request lifecycle feedback, and actions only when the browser must do something imperative. For server-driven synthetic events or attribute flips on live elements without a rerender, use element handles (`Emitter`, `Setter`) from `17-element-handles`.

The `On` callback is optional on all event, form, and hook attrs: with nil `On` the request is still accepted (body discarded) and the hook stays registered, e.g. as an `Emitter` round-trip target. Exception: `AHook[T]` still decodes the body into `T`, so an empty or invalid body answers 400.

Set `Batch: true` on a handler that updates several Doors or stacked/nested components in one action, so the browser applies them together; see `references/09-events.md`. Do not wait in the handler for an update to be applied; to act once it is on the page, use `doors.OnBatch`.

After successful form flows, prefer updating the route source so the page reroutes in place. Do not use hard navigation actions for ordinary in-app transitions.

## Implementation Defaults

### App

`doors.App` is the HTTP entry point. Create with `doors.NewApp(page, options...)`, attach middleware with `app.Use(...)`, then pass to `http.ListenAndServe` or mount as `http.Handler`.

The function passed to `NewApp` is a page factory, not the router: it runs once per page instance, on the full page load that creates it. Use it to bootstrap session state (auth, theme, locale, cookies, headers). Day-to-day routing happens inside the returned root component.

Sessions are lazy: the cookie is set immediately, but session state is allocated only on first actual touch of a session API. Requests that never touch it (static resources, crawlers, middleware-handled requests) allocate none.

### Rendering

- Rendering, state propagation, and hook execution are managed by the Doors runtime. Load data where you render it: query the database or call an API right in the render. If that is too slow, render a skeleton and replace it with a deferred operation; see `references/07-door.md`.
- Ignore the completion channels of Door operations, `Source.Update`/`Mutate`, and `doors.Call` in most cases; there is nothing to check.
- Never wait on them during render or in beam subscriptions. If the result is needed (backpressure in advanced setups, data coming back from the browser), wait in a goroutine of your own with `doors.DetachedContext(ctx)`, or in `doors.Go` when the work should follow a rendered subtree. Only a detached ctx (`DetachedContext`, `InstanceContext`, `doors.Go`, `OnReady`/`OnBatch` callback ctx) delivers a result: every channel first sends a scheduled value, and only a detached ctx gets the second (applied / `Into` result); on any other ctx it closes after the first and an `Into` destination stays unwritten. Read both values. Batches do not change this. See `references/03-context.md#completion-channels`.
- To react after updates use callbacks: `doors.OnSettle` (updates queued for delivery), `doors.OnBatch` (applied in the browser). `OnReady`/`OnBatch` callbacks get a detached ctx; `OnSettle`'s does not and must not block. Use `doors.OnReady` to start work that must not outrun the markup it targets, `doors.OnClean` for teardown when content is cleared, and `doors.HoldSettle` when a handler hands work to another goroutine but indicators, scopes, and the `$hook` promise must stay pending until it finishes.
- Use `doors.Parallel()` only for independent slow render fragments. Do not put it in front of `Bind`, `Effect`, `Route`, or `doors.Door` rendering; dynamic containers already render on the instance goroutine pool.
- Use `doors.Go(f)` for background work scoped to a rendered subtree's lifetime; `f` starts only after the surrounding render cycle is enqueued for delivery, so its Door updates land after the host markup.
- Doors renders dynamic parts into containers it manages. Scripts may set attributes, classes, and styles, show and hide elements, and mount JS islands (e.g. a React app). Never move or remove the dynamic containers themselves: Doors updates them in place and expects to find them where it rendered them.
- Do not return errors from render code: render loading failures, missing data, and other error states as content. A failed render sends nothing to the browser, leaves the previous content on the page but detached, and is only logged as `door rendering error`; see `references/07-door.md`.

### Routing

Prefer typed path models for normal app routing. A path model decodes the URL into a Go value and encodes the same value back into a URL for links, redirects, and programmatic navigation. Path models use one int variant field with prefix tags such as ``Section Section `/:" | docs | guide"` `` or ``Section Section `"/post/:ID":"view | edit"` ``. Use `/` for small models and single pages; use a prefix key with as many shared segments and params as the area needs to define a small area-local model with relative variants.

Old bool marker fields and old ``path:"..."`` tags are compatibility syntax. In old tags, `path` is used as the tag key instead of a path prefix key such as `/`, `/posts`, or `"/post/:ID"`. If you encounter them while changing routing, convert to the int variant prefix-tag form unless the user explicitly asks for a compatibility-only edit.

When changing routing, inspect the existing model first, add variants to the existing model when appropriate, put fallbacks last, and do not treat a route match as authorization. Build routes from groups (`RouteModel[M]`, `RouteMatch`, `RouteValue`, `RouteDerive`) that hold leaves (`RouteComp`, `RouteBind`, `RouteSource`, `RouteBeam`); nest levels in one `doors.Route` or `source.Route` call instead of a second `Route` inside branch content, unless a layout must stay mounted. A leaf always matches, so the fallback is a plain leaf placed last. `.Route` keeps the active branch when the active match stays the same (a `RouteBind` leaf rerenders on value change); a branch inside `Bind` rerenders on every subscribed value change. Do not `Bind` the whole path at the page shell to switch on one field; the ladder is path/model branch key, then narrower derived branch keys, then params/query effects or binds only where consumed.

Don't use raw `<a href="/path">` for in-app links — this causes a full page reload. Always use `doors.ALink`, and set `Batch: true` on navigation links by default: the current view stays intact until the new one is complete, then is replaced at once. See `references/10-navigation.md`.

### State

Use `doors.Source[T]` for writable state and `doors.Beam[T]` for read-only derived or observed state.

Keep identifiers, filters, pagination, selection, route values, and small UI state in Doors state. Load backing data while rendering or handling events instead of turning live page memory into a large cache.

Treat source values as immutable. If a source holds a slice, map, pointer, or mutable struct, replace it with a new value instead of mutating it in place. Apply the granularity ladder to all state, not only URLs: route on branch keys, derive fields, and bind/effect only where consumed.

`Update`/`Mutate` return `<-chan error` completion channels: nil means propagated, `context.Canceled` means superseded by a newer update, closed without a value means suppressed. Ignore them; never wait on one during render or in beam subscriptions.

Render callbacks should render from current state rather than perform route changes or other state mutations. For navigation, update the route source from event handlers, app factory/bootstrap code, or another runtime-managed side-effect path.

### Context

Use the Doors runtime context provided by render code and handlers; see `references/00-gox.md` and `references/03-context.md` for where it is in scope.

Handlers receive their own `ctx`; use that handler context inside handlers.

Use the Doors-provided context for state reads/updates, hooks, links, session/instance APIs, subscriptions, lifecycle-bound work, and Door updates. Use `r.Context()` only for ordinary HTTP/request work.

For app-wide dependencies (DB pool, config, service client) use `doors.NewApp(page, doors.WithValue(key, v))`: `ctx.Value(key)` works in every Doors ctx (page factory, render, handlers, `DetachedContext`/`InstanceContext`/`SessionContext`, `r.Context()`, the hook/resource `*http.Request`). Use an unexported key and a typed helper.

User `context.WithValue` values do not flow into a render subtree automatically; wrap content with the `doors.Ctx(ctx)` proxy to propagate them to nested renders, event handlers, and later door updates. `SessionContext` drops user values but keeps `WithValue` app values.

`doors.HasSession`/`doors.HasInstance` report what a context supports; `doors.IsDocument` reports whether it renders into the page response; `doors.SessionID`/`doors.InstanceID` (note the ID casing) return identifiers; `doors.Logger(ctx)` returns the configured logger; `doors.IDNumber(ctx)` returns an instance-unique `uint64`.

### Components

Components can hold state. Struct components are usually better for significant state or multiple methods.

## Security & Correctness Rules

Keep these rules in the top-level skill because they affect nearly every Doors change.

### URL and Route Trust

- Treat the URL, path params, query params, form values, uploaded filenames/content types, and all browser-sent event data as client-controlled input.
- A path model match means "URL parses", not "authorized".
- Do not store auth, role, permission, tenant, ownership, or other trust-bearing values in the route.
- Keep trust-bearing values in server-owned state: local variables, struct fields, session storage, instance storage, or the database.
- Do not use active links, matched routes, hidden inputs, or client-provided IDs as proof of permission.
- For generated downloads, use fixed or sanitized server-owned filenames; do not derive the download name directly from an uploaded filename.

### Authorization

- Check permissions while deciding what to render. If route and auth state both affect a branch, bind/effect both there; an auth-only `Bind` that merely passes a route source onward is not enough unless that child binds/effects the route.
- If permissions are dynamic and can change between render and handler execution, re-check at the database transaction or service operation level, not merely in the hook handler.

### Hooks and Lifetime

- Hooks are scoped to the UI that produced them. Only the user you rendered to can trigger them while the parent element is mounted.
- When a dynamic parent unmounts, subscriptions (`Bind`, `Effect`, `Sub`), hooks, and mounted Doors inside it are canceled and cleaned up.
- `Door.Static` content belongs to the Door's parent: hooks, subscriptions, `doors.Go`, and lifecycle callbacks registered while rendering it live until the parent's content is cleared, even if the static render fails. For feed-like content that goes final, call `Static` on the item's Door with final content free of hooks and subscriptions.
- A `Door` also has stored state on the Go value. After `Static` or `Unmount`, Door methods can still update stored state for a future render, but they do not auto-remount it.
- Each page open gets its own instance. Session storage is shared across all pages/tabs in the session; instance storage is scoped to one page instance.

### UI Actions and State

- Prefer Doors-managed UI updates first: update `Source`/`Beam` state, render with `Bind`/`Effect`, or update a `Door` before using imperative client actions.
- Use actions only when the browser must do something imperative, such as scroll, emit a JS event, hard navigate, or show timed feedback.
- Use session storage for state shared across browser pages/tabs.
- Use instance storage for one live page instance.
- Use element handles when a stateless live-DOM touch is the simpler model: `Setter` for attribute changes shared across elements, `Emitter` for synthetic DOM events dispatched from server code. Handles change live elements only; a rerendered element returns to its template attributes, so keep durable values in state.

## Reference Inventory

- `references/00-gox.md` - bundled Doors-specific GoX reference
- `references/01-get-started.md` - project setup, starter clone, minimal project, project structure
- `references/03-context.md` - Doors runtime context, `doors.Ctx` user values, Session/Instance/Detached contexts, completion channel semantics (detached vs not), `HasSession`/`HasInstance`/`IsDocument`, API compatibility tables
- `references/04-app.md` - `NewApp`, middleware, `UseFS`, `UseDir`, `UseResource`, HEAD requests, cache constants, mounting
- `references/05-routing.md` - path models, params, query, `Route`, route groups and leaves, nesting, fallbacks, `Location`
- `references/06-state.md` - `Source`, `Beam`, `Bind`, `Effect`, `Sub`, derivation, `TabState`, consistency, skipping
- `references/07-door.md` - low-level dynamic containers: `Inner`, `Outer`, `Static` (content ownership), deferred ops (`DeferredInner`/`DeferredOuter`/`DeferredStatic`, placeholder and loader), `Reload`, `Unmount`, `Once`, completion channels, render errors, lifecycle hooks (`OnReady`/`OnSettle`/`OnBatch`/`OnClean`/`HoldSettle`), growing content
- `references/08-components.md` - reactive components, `Bind` vs `Effect`, struct patterns, constructors, state ownership, lifecycle
- `references/09-events.md` - event attrs, request types, handler flow, forms, key `Key` filters, per-hook `RequestTimeout`, reuse, `Race`, `Batch`
- `references/10-navigation.md` - `ALink`, `Batch`, active links, programmatic navigation, `LocationEncoder`
- `references/11-scopes.md` - blocking, serial, debounce, latest, frame, concurrent, sharing, pipelines
- `references/12-indication.md` - indicators, selectors, combining, `ActionIndicate`
- `references/13-actions.md` - `Call`, `Into`, `ActionEmit[T]`, `ActionScroll`, `ActionIndicate`, `ActionTime`, location actions, `ErrExecution`/`ErrTerminated`/`ErrPathModel`/`ErrPathEncode` sentinels
- `references/14-resources.md` - `ResourceFS`, `ResourceBytes`, resource attrs, cache/type/name/portable, `NewResource` URL in code, external resources
- `references/15-javascript.md` - managed scripts, `AHook`, `$hook`, `$data`, `$on`, emit timing, modules, esbuild
- `references/16-styles.md` - class helper, stylesheet resources, raw/private styles, framework CSS (`d0-r` via constructed stylesheet, no `doors.css`)
- `references/17-element-handles.md` - element handles: `Setter` (attributes), `Emitter` (synthetic events), value semantics, removed `AShared`
- `references/18-storage-auth.md` - session/instance stores, auth, login/logout pattern, OAuth/PKCE flows
- `references/19-session-instance.md` - session/instance lifecycle, lazy sessions, `SessionID`/`InstanceID`, context functions
- `references/20-head-status.md` - title/meta mounting, initial HTTP status
- `references/21-configuration.md` - `Conf` (incl. `ServerDisableHead`), CSP, ESProfile/JSX, `WithID`, `WithPrinter`, error page, session tracker
- `references/22-background-data.md` - background goroutines, polling/external data, `DetachedContext`, any-context Beam reads/subscriptions, `SessionStore.Init`
- `references/23-testing.md` - Go vs Rod test boundaries, e2e harness, waiting rules, agent/dev browser checks
