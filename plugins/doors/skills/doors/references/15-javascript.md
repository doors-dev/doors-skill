# JavaScript

Script resources + Go↔JS bridge (`AHook`, `$hook`, `$data`, `$on`).

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
    type="text/typescript"   // JS (omit), module, typescript, module/typescript
    inline                    // managed script behavior for src resource
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
- `$hook(name, arg?)` — call Go handler, returns promise. Throws `HookErr` on failure (catch for expected failures)
- `$fetch(name, arg?)` — call Go handler, returns raw `Response`
- `$on(name, handler)` — register JS handler for `ActionEmit`. Must be synchronous. Receives `(arg, err)` — `err.kind` tells failure type.
- `$sys.ready()` — promise that resolves when runtime initialized
- `$sys.clean(fn)` — register cleanup on unmount (timers, listeners)
- `$sys.activateLinks()` — re-scan ALink elements after DOM changes
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

Handler search scoped through Door tree — nearest matching wins. Must be synchronous.

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
