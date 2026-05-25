---
name: doors
description: Use when creating, editing, reviewing, debugging, or extending applications built with Doors, the Go server-side interactive UI framework. Covers Doors app structure, routing, reactive state, events/hooks, doors, components, navigation, resources, JavaScript, styles, auth, sessions, background data, configuration, and framework-specific conventions. For GoX template syntax and .gox authoring rules, use the GoX LLM reference instead.
license: Apache-2.0
compatibility: codex, claude-code, opencode
metadata:
  version: "0.1.0"
  language: go
---

# Doors

Doors is a Go framework for building server-side interactive web applications.

Use this skill as the entry point for Doors-specific work. Keep this file as an operating guide and reference router; load detailed API facts from `references/` only when the task needs them.

## Boundary With GoX

Doors apps commonly use GoX templates, but this skill does not teach GoX syntax.

When a task touches `.gox` files, template authoring, generated `.x.go` files, GoX formatting, GoX generation, GoX compile errors, or GoX CLI/module compatibility, first read the GoX LLM reference:

- `https://raw.githubusercontent.com/doors-dev/gox/refs/heads/main/llms.md`

Follow that reference for `.gox` authoring rules, generated-file handling, `gox fmt`, `gox gen`, `gox ver`, and editor/tooling expectations.

Doors-specific rule: if the project already depends on `github.com/doors-dev/doors`, do not add or use `goxx`.

## First Pass Workflow

Before editing a Doors project:

1. Inspect the existing project structure and conventions.
2. Check `go.mod` for `github.com/doors-dev/doors`.
3. If editing `.gox`, read the GoX LLM reference first.
4. Identify the smallest Doors domain involved: app setup, routing, state, components, events, doors, resources, JavaScript, styles, auth, sessions, background data, or configuration.
5. Read only the matching reference files from the map below.
6. Prefer local edits that fit existing routing, state, styling, and auth patterns.
7. Do not edit generated `.x.go` files.
8. Run or suggest `gox fmt`, `gox gen`, and `go test ./...` when appropriate for the change.

Ask the user only for product requirements that cannot be inferred from the code, such as unknown URL shape, ambiguous app section, missing data fields, permissions policy, destructive behavior, or deployment settings.

## Core Mental Model

- Each interactive page is a live server-side instance. There is no virtual DOM.
- Components are static by default: `Main()` renders once and stays. Re-rendering is explicit and targeted — only fragments triggered by `Bind`/`Effect`, `Sub` callbacks, or direct Door method calls (`Inner`, `Outer`, `Static`, `Reload`) from handlers and Sub callbacks re-render. The rest of the tree is untouched.
- State derivation replaces virtual DOM diffing. Instead of rendering everything and diffing, derive narrow beams from one source of truth; only subscribers to changed beams update.
- The current URL is reactive state. Routing usually branches from typed path models and route sources.
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

Read references by task, not all at once.

| Task | Read |
|------|------|
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

## Quick Pattern: Interactive Elements

Read `09-events`, `11-scopes`, `12-indication`, `13-actions` for full options.

Hook attrs can be attached two ways: modifier `(doors.AClick{...})` inside the tag, or proxy `~>doors.AClick{...}` before the element. Both are equivalent. Modifier is more explicit; proxy keeps the tag clean with many fields and drills through wrapping components.

### Click handler

```gox
<button (doors.AClick{
    On: func(ctx context.Context, _ doors.RequestPointer) bool {
        // mutate state, update a Door, etc.
        return false
    },
})>Click Me</button>
```

### Input with reactive state

```gox
~{ input := doors.NewSource("") }
<input (doors.AInput{
    On: func(ctx context.Context, r doors.RequestInput) bool {
        input.Update(ctx, r.Event().Value)
        return false
    },
}) type="text">
~(input.Bind(results))

elem results(query string) {
    // render based on query
}
```

### Navigation link

```gox
~>doors.ALink{Model: path, Indicator: loader} <a>Link</a>
```

With current-page highlighting:

```gox
~>doors.ALink{
    Model:     path,
    Indicator: loader,
    Active:    doors.Active{Indicator: doors.IndicateClass("active")},
} <a>Link</a>
```

### Full lifecycle (scope + indicator + actions)

When overlap or latency matters:

```gox
<button (doors.AClick{
    Scope:     &doors.ScopeBlocking{},
    Indicator: doors.IndicateAttr("aria-busy", "true"),
    Before:    doors.ActionScroll{Selector: "#top"},
    OnError:   doors.ActionIndicate{
        Indicator: doors.IndicateClass("error"),
        Duration:  300 * time.Millisecond,
    },
    On: func(ctx context.Context, r doors.RequestPointer) bool {
        r.After(doors.ActionScroll{Selector: "#result"})
        doors.Call(ctx, doors.ActionEmit{Name: "toast", Arg: "Saved"})
        return false
    },
})>Save</button>
```

### Navigate after form success

After a successful form submission, update the route source — the page re-routes in place. Do not use hard navigation actions for this.

```gox
~>doors.ASubmit[loginData]{
    Scope:     new(doors.ScopeBlocking),
    Indicator: doors.IndicateAttr("aria-busy", "true"),
    On: func(ctx context.Context, r doors.RequestForm[loginData]) bool {
        err := auth.Login(r, r.Data().Email, r.Data().Password)
        if err != nil {
            message.Update(ctx, "Invalid credentials")
            return false
        }
        path.Update(ctx, Path{Route: Dashboard})
        return true
    },
} <form>
    <input name="email" type="email">
    <input name="password" type="password">
    <button type="submit">Login</button>
</form>
```

## Implementation Defaults

### App

`doors.App` is the HTTP entry point. Create with `doors.NewApp(page, options...)`, attach middleware with `app.Use(...)`, then pass to `http.ListenAndServe` or mount as `http.Handler`.

The function passed to `NewApp` is a per-request page factory, not the router. Use it to bootstrap session state (auth, theme, locale, cookies, headers). Day-to-day routing happens inside the returned root component.

### Rendering

- Rendering and state propagation happen on the Doors runtime. It's normal to query DB or call APIs while rendering.
- Dynamic containers render on the instance goroutine pool by default.
- Use `doors.Parallel()` to render independent slow fragments concurrently.
- Use `doors.Go(f)` for background work scoped to a rendered subtree's lifetime.
- Treat dynamic subtrees as runtime-managed. Direct DOM work is possible but should complement the runtime, not race against it.

### Routing

Prefer typed path models for normal app routing. A path model decodes the URL into a Go value and encodes the same value back into a URL for links, redirects, and programmatic navigation.

When changing routing, inspect the existing model first, add variants to the existing model when appropriate, put fallbacks last, and do not treat a route match as authorization.

### State

Use `doors.Source[T]` for writable state and `doors.Beam[T]` for read-only derived or observed state.

Keep identifiers, filters, pagination, selection, route values, and small UI state in Doors state. Load backing data while rendering or handling events instead of turning live page memory into a large cache.

Treat source values as immutable. If a source holds a slice, map, pointer, or mutable struct, replace it with a new value instead of mutating it in place.

### Context

Inside `elem` blocks and `~{ ... }` code blocks, `ctx context.Context` is implicitly in scope. It is the Doors runtime context.

Handlers receive their own `ctx`; use that handler context inside handlers.

Use the Doors-provided context for state reads/updates, hooks, links, session/instance APIs, subscriptions, lifecycle-bound work, and Door updates. Use `r.Context()` only for ordinary HTTP/request work.

### Components

In these docs, "component" means anything satisfying `gox.Comp`: struct components with `Main()`, plain `elem` functions, and Doors helpers such as `Bind`, `Route`, `RouteBeam`, and `Go`.

Both struct and `elem` styles can hold state. Structs are usually better for significant state or multiple methods.

## Security & Correctness Rules

Keep these rules in the top-level skill because they affect nearly every Doors change.

### URL and Route Trust

- Treat the URL, path params, query params, form values, and all browser-sent event data as client-controlled input.
- A path model match means "URL parses", not "authorized".
- Do not store auth, role, permission, tenant, ownership, or other trust-bearing values in the route.
- Keep trust-bearing values in server-owned state: local variables, struct fields, session storage, instance storage, or the database.
- Do not use active links, matched routes, hidden inputs, or client-provided IDs as proof of permission.

### Authorization

- Check permissions while deciding what to render. In most cases this is sufficient because the user can only trigger hooks that were rendered into their mounted UI.
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

- `references/01-get-started.md` - project setup, starter clone, minimal project, project structure
- `references/03-context.md` - implicit GoX ctx, Session/Instance/Detached contexts, API compatibility tables
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
- `references/14-resources.md` - `ResourceFS`, `ResourceBytes`, modifier syntax, cache/type/name, external resources
- `references/15-javascript.md` - managed scripts, `AHook`, `$hook`, `$data`, `$on`, modules, esbuild
- `references/16-styles.md` - class helper, stylesheet resources, raw/private styles
- `references/17-shared-attr.md` - `AShared`, `NewAShared`, `Enable`, `Disable`, `Update`
- `references/18-storage-auth.md` - session/instance stores, auth, login/logout pattern, OAuth/PKCE flows
- `references/19-session-instance.md` - session/instance lifecycle, IDs, context functions
- `references/20-head-status.md` - title/meta mounting, initial HTTP status
- `references/21-configuration.md` - `Conf`, CSP, ESProfile/JSX, `WithID`, error page, session tracker
- `references/22-background-data.md` - background goroutines, polling/external data, `DetachedContext`, `SessionStore.Init`
