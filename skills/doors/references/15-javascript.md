# JavaScript

Script resources + Go↔JS bridge (`AHook`, `$hook`, `$data`, `$on`).

The main pattern: embed a separate CommonJS `.ts` file as a managed script using `src=(resource)` with `type="typescript" inline`. It is essentially an inline script stored in a separate file — it gets auto-wrapped with framework APIs and cannot be bundled.

The TypeScript language server does not know about Doors post-processing — it will show errors for top-level `await` and Doors APIs like `$hook`, `$data`, etc. This is expected and not an issue at runtime.

## Script Shapes

| Shape | How | Runtime |
|-------|-----|---------|
| **Managed inline** | Plain `<script>...</script>` with no `src`/`raw`/non-JS `type` | Gets `$data`, `$hook`, `$fetch`, `$on`, `$sys`, top-level `await` |
| **Managed src** | `<script src=(resource) inline>` | Same as managed inline |
| **Plain linked** | `<script src=(resource)>` | Built through JS pipeline |
| **Module** | `<script src=(resource) type="module" bundle>` | ES module with bundling |
| **Raw** | `raw` attr on any script | Browser loads as-is |

## Script Attrs

```gox
<script src=(resource)
    type="typescript"   // JS (omit), module, typescript, module/typescript
    inline                    // wraps resource content with Doors API for inline usage
    bundle                    // bundle dependencies
    raw                       // skip transformation, serve as-is
    specifier="app"           // register in import map
    profile="react"           // named esbuild profile
    name="app.js"             // readable output filename
    private                   // instance-scoped URL (not publicly reachable)
    nocache>                  // no shared resource caching (for dynamically generated scripts)
</script>
```

## Managed Scripts

Auto-wrapped with:
- `$data(name)` — read server-provided values (string/JSON → direct, `[]byte` → `Promise<ArrayBuffer>`)
- `$hook(name, arg?)` — call Go handler, returns promise. Throws `HookErr` on failure. Check `instanceof HookErr` to distinguish framework errors from other errors.
- `$fetch(name, arg?)` — call Go handler, returns raw `Response`
- `$on(name, handler)` — register JS handler for `ActionEmit`. Must be synchronous. Receives `(arg, err)` — `err.kind` tells failure type.
- `$sys.ready()` — promise that resolves when the page is loaded and runtime initialized. All framework APIs (`$data`, `$hook`, `$fetch`, `$on`) already wait for readiness internally, so this is only needed for non-framework operations that depend on the runtime.
- `$sys.clean(fn)` — register cleanup on unmount (timers, listeners)
- `$sys.activateLinks()` — re-scan `ALink` elements to apply active-link indication. Useful after JavaScript-driven URL fragment changes.
- top-level `await`

Auto-detected request body: `undefined`→no body, `FormData`→multipart, `URLSearchParams`→form-urlencoded, `Blob`→raw blob body, `File`→raw file body, `ReadableStream`→`application/octet-stream`, `ArrayBuffer`/typed arrays→`application/octet-stream`, anything else→JSON.

## Data Binding (Go→JS)

```gox
<script data:userId=(userID) data:theme=(theme)>
    const userId = $data("userId")      // string/JSON → direct value
    const buf   = await $data("logo")   // []byte → Promise<ArrayBuffer>
</script>
```

`data:name=(expr)` is GoX shorthand for `doors.AData{Name: "name", Value: expr}`.

`$data`, `$hook`, and `$fetch` read attrs from the managed script element they run on. Attach `AData`, `AHook`, or `ARawHook` to that same managed inline script, or to the `src` script marked `inline`; a separate module script does not inherit those helpers from another script element.

## Finding Local Elements

When JavaScript needs elements from the component it is rendered with, avoid global IDs first. Put the script inside the component wrapper and query from `document.currentScript.parentElement`:

```gox
<div class="picker">
    <button data-pick="a">A</button>
    <button data-pick="b">B</button>
    <script>
        const root = document.currentScript.parentElement
        const buttons = root.querySelectorAll("[data-pick]")
    </script>
</div>
```

Use this for colocated inline scripts whose target elements are siblings under the same wrapper. If the script is nested deeper or the nearest meaningful wrapper is not the direct parent, use `document.currentScript.closest(".component-class")`. Both forms keep repeated components independent and avoid ID collisions.

When code outside that local script needs a real ID, generate it on the server and pass it through markup/data. Use `doors.IDRand()` for a unique per-render ID, or `doors.IDString(value)` for a stable ID derived from a component property such as title, slug, or URL. For `IDString`, pick a value that is unique in that rendered scope. Both helpers produce selector-compatible IDs.

```gox
~{ panelID := doors.IDRand() }
<section id=(panelID)>
    ...
</section>
<script data:panelID=(panelID)>
    const panel = document.querySelector("#" + $data("panelID"))
</script>
```

Use a stable ID when the same logical item should keep the same handle across renders:

```gox
~{ headingID := doors.IDString(article.URL) }
<h2 id=(headingID)>~(article.Title)</h2>
```

Do not hardcode reusable component IDs such as `id="modal"` or `id="root"` inside components that can appear more than once. Prefer `document.currentScript.parentElement.querySelector(...)` or `document.currentScript.closest(...)` for local behavior, `doors.IDRand()` for unique per-render handles, or `doors.IDString(...)` for deterministic handles from stable data.

## Hooks (JS→Go)

### Typed

```go
type AHook[T any] struct {
    Name      string
    Scope     Scopes
    Indicator Indicators
    On        func(ctx context.Context, r RequestHook[T]) (any, bool)
}
```

Return value marshaled to JSON. Return `false` to keep hook, `true` to remove.

### Raw

```go
type ARawHook struct {
    Name      string
    Scope     Scopes
    Indicator Indicators
    On        func(context.Context, RequestRawHook) bool
}
```
For raw body access, multipart, custom responses.

### Client Side

```js
const result = await $hook("save", {id: 1})        // JSON response, throws HookErr on failure
const resp   = await $fetch("upload", formData)    // raw Response
```

Manual `$hook(...)` and `$fetch(...)` calls throw `HookErr`. Catch it when failure is part of the normal flow.

Request body auto-detected: `undefined` (no body), `FormData` (multipart), `URLSearchParams` (form), `Blob` (raw blob body), `File` (raw file body), `ReadableStream` (octet stream), `ArrayBuffer`/typed arrays (octet stream), other (JSON).

### $on (for ActionEmit)

```gox
<script>
    $on("alert", (message, err) => {
        if (err) { console.log(err.kind); return }
        window.alert(message)
        return "ok"
    })
</script>
```

Handler found by searching the current dynamic node and up the tree. Returns the first match in the current subtree.

## Modules

```gox
<script src=(doors.ResourceLocalFS("web/react/index.tsx"))
    type="module" bundle specifier="app"></script>

<script>
    const { mount } = await import("app")
    mount(document.getElementById("app"))
</script>
```

Preload without execution:
```gox
<link rel="modulepreload" href=(resource) specifier="app">
```

## Esbuild

Default profile: ES2022 target, minified. Configure:
```go
app := doors.NewApp(page, doors.ESProfile{Minify: true, JSX: doors.JSXReact()})
```
Or named profiles via `WithESProfiles`.

## Related

- [resources.md](./14-resources.md) — Generic resource syntax
- [events.md](./09-events.md) — Standard DOM events (prefer over `$hook` for clicks/inputs/forms)
- [actions.md](./13-actions.md) — `ActionEmit`, `$on`
- [configuration.md](./21-configuration.md) — `ESProfile`, `WithESProfiles`
