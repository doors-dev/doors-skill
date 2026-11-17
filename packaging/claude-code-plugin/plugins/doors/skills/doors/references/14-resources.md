# Resources

Doors-managed `src`/`href` values. Turn app-owned content (files, bytes, builds, handlers) into browser URLs. Build a chain, then attach it to the tag as a modifier `<tag (chain)>`, set it as an explicit `src=`/`href=` value, pass it to a script with `data:name=(chain)`, or get its `URL(ctx)` in Go code; on a tag, attributes are the shorter way to write the same chain.

- Plain URL → use a string: `<img src="/assets/logo.png">`
- App content → use a resource: `<img (doors.ResourceLocalFS("./private/logo.png"))>`

## Hook and Hosted

Every resource is served one of two ways:

| | Hook | Hosted |
|---|---|---|
| URL | per render, belongs to the page | from content hash, same for every page/user |
| Access | session cookie only (`410` without), unless portable | public, anyone with the URL |
| Lifetime | until the enclosing content is cleared or page/session ends (`404`) | process lifetime, browser-cached (`ServerCacheControl`, immutable by default) |
| Content | read / handler run on every request | read or built once, kept in RAM |
| Sources | any | static only (`ResourceFS`, `ResourceLocalFS`, `ResourceBytes`, `ResourceString`, `[]byte`) |

```gox
<script (doors.ResourceFS(web, "app.ts").Script())></script>                  ~// hosted
<link rel="stylesheet" (doors.ResourceFS(web, "app.css").Style())>           ~// hosted
<img (doors.ResourceLocalFS("./private/chart.png"))>                          ~// hook, read per request
<a (doors.ResourceBytes(reportPDF).Name("report.pdf"))>Download</a>          ~// hook
```

Tag defaults for a source with no stage:

| Tag | Static source | `ResourceHandler` / `ResourceHook` / `ResourceProxy` |
|---|---|---|
| `<script src>` | built, hosted | hook |
| `<link rel="stylesheet">` | minified, hosted | hook |
| `<link rel="modulepreload">` | built module, hosted | hook |
| `<img>`, `<a>`, `<iframe>`, `<video>`, … | as is, hook, read per request | hook |

Hosted is for stable, public, small content: no large files, nothing user-specific.

## Two Syntaxes

### Builder

Sources:

```go
func ResourceLocalFS(path string) ResourceStatic          // local file
func ResourceFS(fsys fs.FS, entry string) ResourceStatic  // fs.FS entry (embed)
func ResourceBytes(content []byte) ResourceStatic         // in-memory bytes
func ResourceString(content string) ResourceStatic        // in-memory string
func ResourceHandler(handler func(w http.ResponseWriter, r *http.Request)) ResourceDynamic                      // stdlib handler
func ResourceHook(handler func(ctx context.Context, w http.ResponseWriter, r *http.Request) bool) ResourceDynamic // Doors ctx; true = stop serving
func ResourceProxy(url string) ResourceDynamic            // reverse proxy, URL served by Doors
type ResourceExternal = printer.SourceExternal            // direct URL: doors.ResourceExternal("https://...")
```

Stages: a `ResourceStatic` is an asset (served as is) until `.Script()` or `.Style()` switches it to a build; `.Raw()` after either serves unbuilt. `ResourceDynamic` is always a hook and takes only `.Name()`/`.Portable()`.

```go
doors.ResourceFS(assets, "sans.woff2").ContentType("font/woff2").Cache() // hosted asset
doors.ResourceBytes(reportPDF).Name("report.pdf").Portable()             // portable hook
doors.ResourceFS(web, "app.ts").Script().Module().Bundle()               // hosted ES module
doors.ResourceFS(web, "admin.css").Style().Private()                     // built once, hook URL
doors.ResourceFS(web, "vendor.js").Script().Raw()                        // hosted as is
doors.ResourceHandler(api.ServeHTTP).Name("api")                         // hook
```

Any stage goes in four places:

```gox
<img (doors.ResourceFS(assets, "logo.svg").ContentType("image/svg+xml").Cache())>   ~// modifier (default): sets src/href by tag
<pdf-viewer src=(doors.ResourceBytes(manualPDF).Name("manual.pdf"))></pdf-viewer>      ~// src=/href= on a tag not in the modifier mapping
<script data:logo=(doors.ResourceFS(assets, "logo.svg").ContentType("image/svg+xml").Cache())>
    document.getElementById("logo").src = $data("logo")                               // script data: → $data gives the URL string
</script>
```

- Modifier mapping: `href` on `a`, `area`, `base`, `link`; `src` on `audio`, `embed`, `iframe`, `img`, `input`, `script`, `source`, `track`, `video`. `src=(chain)`/`href=(chain)` works on any tag; required on tags outside this mapping, where a modifier is a render error
- `data:name=(chain)` on `<script>` (inline or with `src`): any plain source, handler, or stage; `$data("name")` returns the same URL as `URL(ctx)`; a read/build error fails the render (logged), like a broken `src`. `[]byte` in `data:` stays a binary payload
- Only `src`, `href`, and script `data:` take a resource. Any other attribute (`<video poster>`) panics during render: `resource in "poster": only src, href, and script data: attributes take a resource`; use `URL(ctx)` there
- A module stage as a modifier on `<script>` adds `type="module"`

### Attributes

Attributes set the same things on the tag:

```gox
<img (doors.ResourceFS(assets, "logo.svg")) type="image/svg+xml" cache>
```

| Attribute | Method |
|---|---|
| `name="a.pdf"` | `.Name("a.pdf")` |
| `type="image/svg+xml"` (generic tags) | `.ContentType(t)` |
| `cache` | `.Cache()` |
| `private` | `.Script().Private()`, `.Style().Private()` |
| `nocache` | `.Script().NoCache()`, `.Style().NoCache()`; assets: default |
| `portable` | `.Portable()` |
| `type="module"`, `type="typescript"` | `.Script().Module()`, `.Script().TypeScript()` |
| `bundle`, `raw`, `profile="react"` | `.Bundle()`, `.Raw()`, `.Profile("react")` |

Difference: with attributes the tag decides the kind (`ResourceFS(web, "app.ts")` is a script on `<script>`, an asset on `<a>`); a chain states it (`.Script()` on `<a>` is a render error). Attributes and a chain mix on one tag; a contradiction is an error (see Render Errors).

Shorthands on `src=`/`href=` values only (not as modifiers): `[]byte` → `ResourceBytes`, `func(w, r)` → `ResourceHandler`, `func(ctx, w, r) bool` → `ResourceHook`.

## Combinations

Each block: chain first, attribute form second. Both serve the same URL.

### Read on Every Request

Default for static sources on generic tags: an asset without `.Cache()` is a hook, read per request (a `ResourceLocalFS` image shows edits without restart). Nothing to set:
```gox
<img (doors.ResourceLocalFS("./data/today.png"))>
```

### Cached and Public

`.Cache()`: host a generic asset. Static sources only.
```gox
<img (doors.ResourceFS(assets, "logo.svg").ContentType("image/svg+xml").Cache())>
<img (doors.ResourceFS(assets, "logo.svg")) type="image/svg+xml" cache>
```
Always set a content type when caching: without it the type is sniffed and JS/CSS come out as `text/plain`. Nothing follows `.Cache()`: set `Name`/`ContentType` before it.

### Built Once, Served by Hook

`.Private()`: script/style built and kept in the shared cache, URL is a hook. For scripts/styles that must not be public.
```gox
<script (doors.ResourceFS(web, "admin.ts").Script().Bundle().Private())></script>
<script (doors.ResourceFS(web, "admin.ts")) bundle private></script>
```
On generic tags `private` changes nothing (already a hook). On handlers it is accepted and changes nothing.

### Rebuilt Every Render

`.NoCache()`: script/style built on every render, no shared cache, served by hook. For output generated per render.
```gox
<link rel="stylesheet" (doors.ResourceString(themeCSS(user)).Style().NoCache())>
<link rel="stylesheet" (doors.ResourceString(themeCSS(user))) nocache>
```
On generic tags `nocache` is the default.

### Portable

`.Portable()`: hook URL with its own access, works without the session cookie (Android WebView downloads, in-app browsers, apps opening links outside the page's cookie jar).
```gox
<a (doors.ResourceBytes(reportPDF).Name("report.pdf").Portable()) download>Download</a>
<a (doors.ResourceBytes(reportPDF)) name="report.pdf" portable download>Download</a>
```
- Bearer link: anyone holding the URL can load it while the content lives
- Still dies when the content is cleared, the instance or session ends, or a one-shot hook returns `true`
- Requests need no cookie and create no session; the handler still sees the page's session, the stripped `r.URL.Path` and `Doors-Hook-Prefix`
- Works on any hook: assets, handlers, `.Private()`/`.NoCache()` scripts and styles; a script/style with neither acts as `.Private()`
- `.Portable()` + `.Cache()` is an error

### Not Served by Doors

Plain strings pass through. `doors.ResourceExternal("https://...")` is a Go type conversion (not a constructor) for a direct browser URL; when the tag renders with the page it also adds the exact URL to CSP: `script-src` for `<script>` and `modulepreload` links, `style-src` for stylesheet links. Later updates add nothing; see CSP in [configuration.md](./21-configuration.md).
```gox
<link (doors.ResourceExternal("https://cdn.example.com/app.css")) rel="stylesheet">
```
For images, anchors, iframes etc. configure the matching CSP directive (`ImgSources`, `FrameSources`, …) yourself. Direct URLs take none of `cache`, `private`, `nocache`, `portable`.

## Reference

### Stages

Every chain ends as `HookResource` or `CacheableResource`:

```go
ResourceStatic        // asset by default
    .Name(n) .ContentType(t)              → AssetResource
    .Cache()                              → CacheableResource
    .Portable()                           → HookResource
    .Script()                             → ScriptResource
    .Style()                              → StyleResource
AssetResource         // after Name/ContentType; no Script/Style
    .Name(n) .ContentType(t)              → AssetResource
    .Cache()                              → CacheableResource
    .Portable()                           → HookResource
ScriptResource        // built, hosted
    .Name(n) .Bundle() .Module() .TypeScript() .Profile(p) → ScriptResource
    .Raw()                                → RawResource
    .Private() .NoCache() .Portable()     → HookResource
StyleResource         // minified, hosted
    .Name(n)                              → StyleResource
    .Raw()                                → RawResource
    .Private() .NoCache() .Portable()     → HookResource
RawResource           // served unbuilt, hosted
    .Name(n)                              → RawResource
    .Private() .NoCache() .Portable()     → HookResource
ResourceDynamic       // handler/hook/proxy: always hook
    .Name(n) .Portable()                  → HookResource
HookResource          .Name(n) .Portable()
CacheableResource     final (no Name; set Name before Cache())
```

- `Name` keeps the stage type on Script/Style/Raw/Asset/Hook stages; on `ResourceStatic` it gives `AssetResource`, on `ResourceDynamic` it gives `HookResource`, so call `.Script()`/`.Style()` first
- `Raw()` drops earlier `Bundle`/`TypeScript`/`Profile`, keeps `Module`
- Signatures: `Resource` (any source except `ResourceExternal`), `ServedResource` (any stage), `CacheableResource` (what `UseResource` takes)

### Attribute Details

- `name`: readable filename at URL end (hosted URLs keep the hash); fixed or sanitized, never echo uploaded names
- `type`: Content-Type on generic tags; error on handlers/hooks/proxies (they set their own); on `<script>` selects script kind
- `cache`: host; static sources only
- Only one of `cache`, `private`, `nocache`
- Handlers/hooks/proxies take `name` and `portable`; `private` is a no-op; `cache`/`nocache` are errors
- Script/style attrs (`inline`, `bundle`, `raw`, `profile`, `specifier`): see [javascript.md](./15-javascript.md), [styles.md](./16-styles.md)
- If the exact response type matters for a hook, use `ResourceHandler`/`ResourceHook` and set `Content-Type` yourself

### Render Errors

- Script stage on a tag other than `<script>`/`<link rel="modulepreload">`; style stage on a tag other than `<link rel="stylesheet">`
- Non-module script stage on `modulepreload` unless the tag has `type="module"`
- `ContentType` stage on `<script>` or a stylesheet link
- Attribute contradicting the chain: `.NoCache()` + `cache`, `.Bundle()` + `raw`
- `portable` + `cache`
- Not errors: plain source or asset stage on script/stylesheet tags; the tag decides the kind (`ResourceFS(web, "app.ts").Name("app.js")` on `<script>` is built)

### Handlers, Hooks, and Proxies

- Always a hook; dies with the content that rendered it
- Handler sees the part after the hook URL as `r.URL.Path` (including the name); `Doors-Hook-Prefix` = hook URL without the name
- Requests run concurrently
- `ResourceHook` gets the Doors ctx; returning `true` stops serving
- `ResourceProxy` with an unparsable URL fails with `500`
- Request bodies are NOT bounded by `ServerRequestBodyLimit`; limit yourself if you read the body

### URL in Code

`URL(ctx) (string, error)` returns the URL the same chain produces on a tag or in a script `data:`. For Go code that needs the string: an attribute other than `src`/`href`/script `data:` (`<video poster>`), a `data-*` attribute read by a library, a value stored outside the render. In markup prefer the modifier, `src=`/`href=`, or `data:name=(chain)`.
- In code a plain source is an asset: `.Script()`/`.Style()` for script/stylesheet URLs; `.ContentType(t).Cache()` for a hosted asset
- Errors: source cannot be read or built; `context.Canceled` for a hook once the content is cleared (that render never reaches the browser); panics if `ctx` is not a Doors render/handler ctx
- Never return `err` as an attribute value (its text lands in HTML)
- Hook URL after content cleared → `404`; without cookie → `410`
- Removed APIs: `NewHook(ctx, r)` → `r.URL(ctx)`; `NewResource(ctx, r, t)` → `r.ContentType(t).Cache().URL(ctx)` (JS/CSS: `r.Script().URL(ctx)` / `r.Style().URL(ctx)`); handler constructors now return `ResourceDynamic`

## Recipes

### Module URL in Code

Import a module without the import map: `data:` takes the chain, the script calls `import()` on `$data`:
```gox
<div id="chart"></div>
<script data:chart=(doors.ResourceFS(web, "chart.ts").Script().Module().Bundle())>
    const { draw } = await import($data("chart"))
    draw(document.getElementById("chart"))
</script>
```
- `import()` needs `.Module().Bundle()`: `.Bundle()` alone outputs CommonJS, `.Module()` alone keeps relative imports the browser cannot resolve
- No import map involved, so it works in content first rendered by a later update; modules shared by name use `specifier`, see [javascript.md](./15-javascript.md)
- A build error fails the render and is logged, like a broken `src`

### App-Wide Module URL

In markup a hosted chain already reuses its build (every `data:chart=(...)` resolves to the same URL). When Go code needs the string itself (stored, passed outside the render), compute it once with a per-resource helper backed by a package-level store:
```go
var urls = doors.NewStore()

type chartKey struct{}

func ChartModule(ctx context.Context) string {
    return urls.Init(chartKey{}, func() any {
        url, err := doors.ResourceFS(web, "chart.ts").Script().Module().Bundle().URL(ctx)
        if err != nil {
            panic(err)
        }
        return url
    }).(string)
}
```
- A panic fails the render that called the helper; nothing is stored, the next call retries
- Hosted (cached) chains only: a hook URL dies with the first page's content
- Store is per process

### Served Once

`ResourceHook` handler returning `true` stops serving after that request:
```gox
<a (doors.ResourceHook(func(ctx context.Context, w http.ResponseWriter, r *http.Request) bool {
    w.Header().Set("Content-Type", "application/pdf")
    w.Write(reportPDF)
    return true
}).Name("report.pdf"))>Download once</a>
```

### Hosted at a Fixed Path

`doors.UseResource(path, CacheableResource)` serves a hosted chain at a chosen path (font referenced from CSS, script embedded on other sites). Version the path: `ServerCacheControl` is immutable by default. See [app.md](./04-app.md).
```go
app.Use(doors.UseResource("/embed/widget.v3.js", doors.ResourceFS(web, "widget.ts").Script().Bundle()))
```

## Custom Endpoints

`<script data:api=(doors.ResourceHandler(mux.ServeHTTP))>` gives browser code its own HTTP endpoint (island API, `EventSource`, `WebSocket`, third-party widget); `$data("api")` is the path. In Go code `doors.ResourceHandler(mux.ServeHTTP).URL(ctx)` gives the same path; its only error is `context.Canceled` after the content is cleared (that render never reaches the browser).

Requests:
- Returned path has no trailing slash; append `/users/42`, `?q=1`
- Handler sees the part after the endpoint as `r.URL.Path`, always starting with `/` (`url` and `url/` both give `/`); escaped segments stay in `r.URL.RawPath`, query kept, `r.RequestURI` is the original
- `Doors-Hook-Prefix` request header = endpoint path
- Any method; requests run concurrently, so synchronize shared state yourself
- `doors.WithValue` values are on `r.Context()`. Use `ResourceHook` when you need the Doors `ctx`; return `true` to remove the endpoint after that request
- `.Portable()` for clients without the cookie (e.g. `EventSource` from a WebView)

Redirects: an absolute location like `/new` goes to the site root. Build it from the prefix:
```go
http.Redirect(w, r, r.Header.Get("Doors-Hook-Prefix")+"/new", http.StatusFound)
```
`http.ServeMux` redirects on its own (`/files` → `/files/`, paths with `//` or `..`) and those leave the endpoint. Register the exact paths the client calls.

Lifetime: the endpoint lives as long as the content it was created in (a component for widget scope, the page root for page-wide). After the content is cleared or the page/session ends, new requests get `404`/`410`; treat both as "page gone". Running requests are not interrupted, but a `ResourceHook` ctx is canceled, so long-lived handlers watch `ctx.Done()`.

Streaming and sockets:
- The writer supports `http.Flusher` (SSE) and `http.Hijacker` (WebSocket upgrade, HTTP/1.1)
- Doors does not close sockets; close on ctx end: `stop := context.AfterFunc(ctx, func() { c.Close() })`
- Client side: `$sys.clean(() => es.close())`
- `app.Use` middleware that wraps the writer must keep `Flusher` and `Hijacker`

Island recipe:
```gox
<head>
    <link rel="modulepreload" href=(dashboardJS) specifier="dashboard">
</head>
```
```gox
elem (d *Dashboard) Main() {
    <div id="app"></div>
    <script data:api=(doors.ResourceHandler(d.api().ServeHTTP))>
        const { mount } = await import("dashboard")
        mount(document.getElementById("app"), $data("api"))
    </script>
}
```
- Register the module in the head: the import map ships with the page, so `import("dashboard")` works when the island first appears in a later update
- `d.api()` returns one `http.ServeMux` routing sub-paths (`"GET /users/{id}"`); client calls `${api}/users`
- Same-origin, so `fetch` sends the session cookie and default CSP allows it

Use `$hook` (`AHook`/`ARawHook`) to enhance page logic; use a custom endpoint when the client brings its own code and speaks plain HTTP. For static files the client loads, pass a hosted chain in `data:` (`data:css=(doors.ResourceBytes(css).Style())`, `data:logo=(doors.ResourceFS(fsys, "logo.png").ContentType("image/png").Cache())`).

## Rules

- Existing URL → string or `ResourceExternal`; app content → resource chain
- State the kind in the chain (`.Script()`, `.Style()`, asset by default); attributes are the shorter way to write it on a tag
- Host (`.Cache()`, default scripts/styles) only stable, public, small content
- `.Private()`/`.NoCache()` for scripts/styles that must not be public
- Cached asset → always `ContentType`
- `.Portable()` for links fetched outside the page
- `URL(ctx)` only when the URL leaves `src`, `href`, or script `data:`; in code: `.Script()`/`.Style()` for script/stylesheet URLs, `.Module().Bundle()` for `import()`
- Version `UseResource` paths

## Related

- [javascript.md](./15-javascript.md) — Script build attrs, modules
- [styles.md](./16-styles.md) — Stylesheet attrs
- [app.md](./04-app.md) — `UseResource` for fixed public paths
