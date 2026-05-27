---
name: doors
description: Always use this skill whenever creating, editing, reviewing, debugging, or extending any Doors project, even for small changes. Do not attempt Doors-specific APIs from memory. Always read the bundled Doors-specific GoX reference first. Covers Doors app structure, routing, reactive state, events/hooks, doors, components, navigation, resources, JavaScript, styles, auth, sessions, background data, configuration, GoX, and framework-specific conventions.
license: Apache-2.0
metadata:
  version: "0.1.4"
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
3. Check `go.mod` for `github.com/doors-dev/doors`.
4. Identify the smallest Doors domain involved: app setup, routing, state, components, events, doors, resources, JavaScript, styles, auth, sessions, background data, or configuration.
5. Read matching `references/` files from the map below; `./docs` and code fact-check them, not replace them.
6. Prefer local edits that fit existing routing, state, styling, and auth patterns.
7. When browser/runtime behavior is unclear and no reliable browser controller is available, use a short Rod check or temporary Go test to inspect the real page. Convert it into a committed e2e test when it verifies user-facing behavior or prevents a regression; delete it when it was only exploratory. Do not use Rod for pure logic that ordinary Go tests cover.
8. Run or suggest the appropriate formatting, generation, and test commands for the change.

Ask the user only for product requirements that cannot be inferred from the code, such as unknown URL shape, ambiguous app section, missing data fields, permissions policy, destructive behavior, or deployment settings.

## Core Mental Model
- Each interactive page is a live server-side instance. There is no virtual DOM.
- Components are static by default: `Main()` renders once and stays. Re-rendering is explicit and targeted — only fragments triggered by `Bind`/`Effect`, `Sub` callbacks, or direct Door method calls (`Inner`, `Outer`, `Static`, `Reload`) from handlers and Sub callbacks re-render. The rest of the tree is untouched.
- State derivation replaces virtual DOM diffing. For all reactive state, use a ladder: branch key owned at that level (often derived), narrower branches, then field/param/query binds only in consuming fragments.
- `Route` swaps only when the matched branch changes; `Bind`/`Effect` rerender on subscribed value changes, so derive before binding.
- Browser events call server handlers bound to the live page instance. If a subtree disappears, hooks and dynamic bindings inside it disappear too.
- A session is shared across browser pages/tabs. An instance is one live page with its own render tree, handlers, subscriptions, and lifecycle.

### Concurrency

- Calls to the same hook are serialized — one at a time, in order of arrival. Different hooks can run in parallel.
- Scopes prevent UI artifacts from parallel hooks (e.g. blocking a related hook while another is in progress). Scopes are a client-side scheduling hint for UX, not a concurrency guarantee — do not rely on them for data safety.
- When working with state beyond `doors.Source`/`doors.Beam` (plain struct fields, slices, maps, external caches), you must handle concurrency yourself. `Source`/`Beam` mutations are safe to call from any context; plain Go state is not.
- Door content rendering and state propagation run in parallel across independent subtrees, but are coordinated so a render cycle sees one coherent view of all sources and derived beams.

Key primitives:

| Primitive | Purpose |
|-----------|---------|
| `Source[T]` | Writable reactive value |
| `Beam[T]` | Read-only derived or observed value |
| `Door` | Dynamic DOM placeholder for explicit partial updates |
| `Route*` | State-based branching between views |
| Hook attrs (`AClick`, `AInput`, `ASubmit`, etc.) | Server-bound DOM events |

## Reference Map
After `references/00-gox.md`, read remaining references by task, not all at once.

| Task | Read |
|------|------|
| Always read before any Doors work | `references/00-gox.md` |
| Create a project, inspect starter layout, or add static files | `references/01-get-started.md`, `references/04-app.md`, `references/21-configuration.md` |
| Work with app creation, middleware, mounting, static dirs, or resources at fixed paths | `references/04-app.md` |
| Choose the right context, start goroutines, wait on X* methods, or handle detached work | `references/03-context.md` |
| Define/edit routes, path models, route variants, params, query, or fallbacks | `references/05-routing.md`, `references/10-navigation.md` |
| Work with `Source`, `Beam`, `Bind`, `Effect`, `Sub`, derived state, or consistency | `references/06-state.md` |
| Update part of a page explicitly without full re-render | `references/07-door.md`, `references/06-state.md` |
| `Bind`/`Effect` not enough — lazy loading, appending content, collections of dynamic regions, or other patterns needing low-level Door control | `references/07-door.md` |
| Build a reactive component or choose `Bind` vs `Effect` | `references/08-components.md` |
| Add click/input/change/submit/key/focus handlers or forms | `references/09-events.md`, `references/11-scopes.md`, `references/12-indication.md`, `references/13-actions.md` |
| Add navigation links, active links, or programmatic navigation | `references/10-navigation.md`, `references/12-indication.md` |
| Add loading/pending feedback during requests (indicators, CSS classes, attributes) | `references/12-indication.md` |
| Control request scheduling: prevent double-clicks, debounce, queue, cancel stale | `references/11-scopes.md` |
| Run browser-side actions before/after/on-error, emit JS events, scroll, or hard navigate | `references/13-actions.md` |
| Serve images, downloads, embedded files, or external URLs | `references/14-resources.md` |
| Add inline scripts, managed scripts, JS modules, Go-to-JS data, or JS-to-Go hooks | `references/15-javascript.md` |
| Add stylesheets, Tailwind classes, inline styles, or class composition | `references/16-styles.md` |
| Sync one attribute across multiple elements | `references/17-shared-attr.md` |
| Add login/logout/auth, OAuth/PKCE flows, or session/instance storage | `references/18-storage-auth.md`, `references/19-session-instance.md`, `references/06-state.md` |
| Control session or instance lifetime | `references/19-session-instance.md` |
| Set page title, meta tags, or initial HTTP status | `references/20-head-status.md` |
| Configure CSP, timeouts, esbuild, server ID, error pages, or session tracking | `references/21-configuration.md` |
| Push data from background sources such as polling, Kafka, or Watermill into reactive state | `references/22-background-data.md`, `references/03-context.md` |
| Test a Doors app or design an app-level e2e test harness | `references/23-testing.md` |

## Interaction Defaults

Read `09-events`, `11-scopes`, `12-indication`, and `13-actions` before changing interactive elements. Use Doors event attrs for normal browser events, scopes for request scheduling, indication for request lifecycle feedback, and actions only when the browser must do something imperative.

After successful form flows, prefer updating the route source so the page reroutes in place. Do not use hard navigation actions for ordinary in-app transitions.

## Implementation Defaults

### App

`doors.App` is the HTTP entry point. Create with `doors.NewApp(page, options...)`, attach middleware with `app.Use(...)`, then pass to `http.ListenAndServe` or mount as `http.Handler`.

The function passed to `NewApp` is a per-request page factory, not the router. Use it to bootstrap session state (auth, theme, locale, cookies, headers). Day-to-day routing happens inside the returned root component.

### Rendering

- Rendering and state propagation happen on the Doors runtime. It's normal to query DB or call APIs while rendering.
- Dynamic containers render on the instance goroutine pool by default.
- Use `doors.Parallel()` only for independent slow render fragments. Do not put it in front of `Bind`, `Effect`, `Route`, or `doors.Door` rendering; dynamic containers already render on the instance goroutine pool.
- Use `doors.Go(f)` for background work scoped to a rendered subtree's lifetime.
- Treat dynamic subtrees as runtime-managed. Direct DOM work is possible but should complement the runtime, not race against it.

### Routing

Prefer typed path models for normal app routing. A path model decodes the URL into a Go value and encodes the same value back into a URL for links, redirects, and programmatic navigation.

When changing routing, inspect the existing model first, add variants to the existing model when appropriate, put fallbacks last, and do not treat a route match as authorization. Prefer `doors.Route`, `RouteModel`, `source.Route`, `RouteMatch`, `RouteDerive`, `RouteValue`, and defaults for dispatch. `.Route` keeps the active branch when the active match stays the same; a branch inside `Bind` rerenders on every subscribed value change. Do not `Bind` the whole path at the page shell to switch on one field; the ladder is path/model branch key, then narrower derived branch keys, then params/query effects or binds only where consumed.

### State

Use `doors.Source[T]` for writable state and `doors.Beam[T]` for read-only derived or observed state.

Keep identifiers, filters, pagination, selection, route values, and small UI state in Doors state. Load backing data while rendering or handling events instead of turning live page memory into a large cache.

Treat source values as immutable. If a source holds a slice, map, pointer, or mutable struct, replace it with a new value instead of mutating it in place. Apply the granularity ladder to all state, not only URLs: route on branch keys, derive fields, and bind/effect only where consumed.

Render callbacks should render from current state rather than perform route changes or other state mutations. For navigation, update the route source from event handlers, app factory/bootstrap code, or another runtime-managed side-effect path.

### Context

Use the Doors runtime context provided by render code and handlers; see `references/00-gox.md` and `references/03-context.md` for where it is in scope.

Handlers receive their own `ctx`; use that handler context inside handlers.

Use the Doors-provided context for state reads/updates, hooks, links, session/instance APIs, subscriptions, lifecycle-bound work, and Door updates. Use `r.Context()` only for ordinary HTTP/request work.

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
- A `Door` also has stored state on the Go value. After `Static` or `Unmount`, Door methods can still update stored state for a future render, but they do not auto-remount it.
- Each page open gets its own instance. Session storage is shared across all pages/tabs in the session; instance storage is scoped to one page instance.

### UI Actions and State

- Prefer Doors-managed UI updates first: update `Source`/`Beam` state, render with `Bind`/`Effect`, or update a `Door` before using imperative client actions.
- Use actions only when the browser must do something imperative, such as scroll, emit a JS event, hard navigate, or show timed feedback.
- Use session storage for state shared across browser pages/tabs.
- Use instance storage for one live page instance.
- Use `AShared` for one shared attribute across elements when that is the simpler model.

## Reference Inventory

- `references/00-gox.md` - bundled Doors-specific GoX reference
- `references/01-get-started.md` - project setup, starter clone, minimal project, project structure
- `references/03-context.md` - Doors runtime context, Session/Instance/Detached contexts, API compatibility tables
- `references/04-app.md` - `NewApp`, middleware, `UseFS`, `UseDir`, `UseResource`, cache constants, mounting
- `references/05-routing.md` - path models, params, query, `Route`, `RouteModel`, `Location`
- `references/06-state.md` - `Source`, `Beam`, `Bind`, `Effect`, `Sub`, derivation, consistency, skipping
- `references/07-door.md` - low-level dynamic containers: `Inner`, `Outer`, `Static`, `Reload`, `Unmount`, X* variants, lifecycle
- `references/08-components.md` - reactive components, `Bind` vs `Effect`, struct patterns, constructors, state ownership, lifecycle
- `references/09-events.md` - event attrs, request types, handler flow, forms, reuse
- `references/10-navigation.md` - `ALink`, active links, programmatic navigation, `LocationEncoder`
- `references/11-scopes.md` - blocking, serial, debounce, latest, frame, concurrent, sharing, pipelines
- `references/12-indication.md` - indicators, selectors, combining, `ActionIndicate`
- `references/13-actions.md` - `Call`, `XCall`, `ActionEmit`, `ActionScroll`, `ActionIndicate`, location actions
- `references/14-resources.md` - `ResourceFS`, `ResourceBytes`, resource attrs, cache/type/name, external resources
- `references/15-javascript.md` - managed scripts, `AHook`, `$hook`, `$data`, `$on`, modules, esbuild
- `references/16-styles.md` - class helper, stylesheet resources, raw/private styles
- `references/17-shared-attr.md` - `AShared`, `NewAShared`, `Enable`, `Disable`, `Update`
- `references/18-storage-auth.md` - session/instance stores, auth, login/logout pattern, OAuth/PKCE flows
- `references/19-session-instance.md` - session/instance lifecycle, IDs, context functions
- `references/20-head-status.md` - title/meta mounting, initial HTTP status
- `references/21-configuration.md` - `Conf`, CSP, ESProfile/JSX, `WithID`, error page, session tracker
- `references/22-background-data.md` - background goroutines, polling/external data, `DetachedContext`, `SessionStore.Init`
- `references/23-testing.md` - Go vs Rod test boundaries, e2e harness, waiting rules, agent/dev browser checks
