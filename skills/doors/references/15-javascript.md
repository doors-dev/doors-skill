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
- `$on(name, handler)` — register JS handler for `ActionEmit`. May return a value or a Promise; the resolved value is delivered to `Into`. Receives `(arg, err)` — `err` set only for `OnError`-dispatched emits, `err.kind` tells failure type.
- `$sys.ready()` — promise that resolves when the page is loaded and runtime initialized. All framework APIs (`$data`, `$hook`, `$fetch`, `$on`) already wait for readiness internally, so this is only needed for non-framework operations that depend on the runtime.
- `$sys.clean(fn)` — register cleanup on unmount (timers, listeners)
- `$sys.activateLinks()` — re-scan `ALink` elements to apply active-link indication. Useful after JavaScript-driven URL fragment changes.
- `$sys.emit(target, event)` — dispatch a DOM event from JS and await every hook request it triggers (including `HoldSettle` and `After` actions); resolves to the number of hook requests, rejects with `HookErr` on any failure (hooks canceled by a scope or by `RaceStrict`, or `Keys`-filtered, count as failures). Client counterpart of `doors.Emitter`. Build the event yourself (`new PointerEvent("click", {bubbles: true})`); safe at script top level.
- top-level `await`

Auto-detected request body: `undefined`→no body, `FormData`→multipart, `URLSearchParams`→form-urlencoded, `Blob`→raw blob body, `File`→raw file body, `ReadableStream`→`application/octet-stream`, `ArrayBuffer`/typed arrays→`application/octet-stream`, anything else→JSON.

## Data Binding (Go→JS)

```gox
<script data:userId=(userID) data:theme=(theme)>
    const userId = $data("userId")      // string/JSON → direct value
    const buf   = await $data("logo")   // []byte → Promise<ArrayBuffer>
</script>
```

`data:name=(expr)` is GoX shorthand for `doors.AData{Name: "name", Value: expr}`. Values are encoded at render time (string → text, `[]byte` → binary, else JSON); a value that fails to encode fails the render (see Render errors in `07-door.md`).

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
~~ panelID := doors.IDRand() ~~
<section id=(panelID)>
    ...
</section>
<script data:panelID=(panelID)>
    const panel = document.querySelector("#" + $data("panelID"))
</script>
```

Use a stable ID when the same logical item should keep the same handle across renders:

```gox
~~ headingID := doors.IDString(article.URL) ~~
<h2 id=(headingID)>~(article.Title)</h2>
```

Do not hardcode reusable component IDs such as `id="modal"` or `id="root"` inside components that can appear more than once. Prefer `document.currentScript.parentElement.querySelector(...)` or `document.currentScript.closest(...)` for local behavior, `doors.IDRand()` for unique per-render handles, or `doors.IDString(...)` for deterministic handles from stable data.

## Hooks (JS→Go)

### Typed

```go
type AHook[T any] struct {
    Name           string
    Scope          Scopes
    Indicator      Indicators
    RequestTimeout time.Duration  // overrides Conf.RequestTimeout for this hook
    Race           Race           // how overlapping calls are handled, see Race below
    On             func(ctx context.Context, r RequestHook[T]) (any, bool)
}
```

Return value marshaled to JSON. Return `false` to keep hook, `true` to remove. `On` optional — nil still decodes the body into `T` (empty or invalid body answers 400), then answers `null`; the hook stays.

### Raw

```go
type ARawHook struct {
    Name           string
    Scope          Scopes
    Indicator      Indicators
    RequestTimeout time.Duration
    Race           Race
    On             func(context.Context, RequestRawHook) bool
}
```
For raw body access, multipart, custom responses.

### Race

Both hook attrs take `Race`, same as event attrs (see `09-events.md`): `doors.RaceSerial` (default, one at a time in order of arrival), `doors.RaceParallel`, `doors.RaceStrict`.

With `Race: doors.RaceParallel`, calls to the same hook run concurrently instead of one at a time. Handler must synchronize shared state itself. Returning `true` stops new calls; hook removed once running calls finish. For long-held streaming responses and independent parallel requests.

With `Race: doors.RaceStrict`, a call that arrives after a newer one is not run; its `$hook`/`$fetch` rejects with a canceled `HookErr`.

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
        return "ok"            // delivered to ActionEmit[string].Into
    })
    $on("confirm", async (q) => await showDialog(q))  // Promise OK
</script>
```

Lookup starts at the Door the `ActionEmit` is dispatched from and walks out to the root — nearest registered handler wins; the action fails when none is reachable. A returned Promise resolves to the action result.

Emit timing: a managed script loads from its own URL and runs once the browser has fetched it, unordered relative to Doors calls. An `ActionEmit` issued by the same render that inserts the script can arrive before `$on` registers and fails with `handler … not found`. When the emit must reach a freshly rendered script, call a `$hook` from the script after registering its handlers and issue the emit from that hook's handler:

```gox
<script (doors.AHook[bool]{
    Name: "ready",
    On: func(ctx context.Context, r doors.RequestHook[bool]) (any, bool) {
        doors.Call(ctx, doors.ActionEmit[any]{Name: "show", Arg: "hello"})
        return nil, true
    },
})>
    $on("show", (msg) => console.log(msg))
    await $hook("ready", true)
</script>
```

## Modules

```gox
<script src=(doors.ResourceLocalFS("web/react/index.tsx"))
    type="module" bundle specifier="app"></script>

<script>
    const { mount } = await import("app")
    mount(document.getElementById("app"))
</script>
```

`specifier="app"` registers the module in the page's import map under that name, so any managed script can `await import("app")` to get its exports. This is the whole point of `specifier` — it's how you reference a server-served module from client code. `specifier` is only valid on modules (a `<script type="module">` or a `<link rel="modulepreload">`); using it elsewhere is an error.

### Pre-bundled module as bytes

When the module is **already a self-contained ESM bundle** (e.g. built by an external esbuild/Bun/Vite step and embedded with `//go:embed`), serve the bytes directly and skip `bundle` — there are no dependencies left for Doors to resolve:

```go
//go:embed dist/editor.js
var EditorScript []byte // already-bundled ESM, exports createEditor
```

```gox
<link rel="modulepreload" href=(EditorScript) specifier="editor" name="editor.js">
```
```gox
<script>
    const { createEditor } = await import("editor")
    createEditor({ target: document.getElementById("editor") })
</script>
```

`href=([]byte)` (or `src=`) becomes a cached, public script resource; with `specifier` set it is registered in the import map. Module format is the default for `modulepreload` and `type="module"`, so no `type`/`bundle` attrs are needed.

- Use **`bundle`** only to make Doors' esbuild bundle dependencies *from source* (e.g. a `.tsx` entry that imports from `node_modules`).
- Use a **plain pre-bundled `[]byte`/`ResourceLocalFS` module** (no `bundle`) when an external tool already produced the bundle.

Preload without execution — a `modulepreload` link both preloads the bytes and (with `specifier`) registers the import-map entry, without running the module until something `import()`s it:
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
