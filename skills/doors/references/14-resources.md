# Resources

Doors-managed `src`/`href` values. Turn app-owned content into browser URLs.

## When to Use

- Plain URL → use a string: `<img src="/assets/logo.png">`
- App content → use a resource: `<img src=(doors.ResourceLocalFS("./private/logo.png"))>`

## Source Constructors

```go
func ResourceLocalFS(path string) ResourceStatic              // local file
func ResourceFS(fsys fs.FS, entry string) ResourceStatic      // embedded file
func ResourceBytes(content []byte) ResourceStatic             // in-memory bytes
func ResourceString(content string) ResourceStatic            // in-memory string
func ResourceHook(handler func(ctx context.Context, w http.ResponseWriter, r *http.Request) bool) Resource  // custom handler
func ResourceHandler(handler func(w http.ResponseWriter, r *http.Request)) Resource  // stdlib-style handler
func ResourceProxy(url string) Resource                       // reverse proxy
func NewHook(ctx context.Context, r Resource) (string, bool)  // custom endpoint URL, see Custom Endpoints; body NOT bounded by ServerRequestBodyLimit
type ResourceExternal = printer.SourceExternal                // direct external URL type; use doors.ResourceExternal("https://...")
```

## Shorthands

On `src=` and `href=`:

| Value type | Treated as |
|------------|------------|
| `[]byte` | `ResourceBytes(...)` |
| `func(w http.ResponseWriter, r *http.Request)` | `ResourceHandler(...)` |
| `func(ctx context.Context, w http.ResponseWriter, r *http.Request) bool` | `ResourceHook(...)` |

```gox
<img src=(pngBytes)>                                     // []byte → ResourceBytes
<a href=(pdfBytes) name="report.pdf">Download</a>
<img src=(func(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "image/svg+xml")
    w.Write(chartSVG)
}) name="chart.svg">
```

## Attach

`doors.Resource*` is an **attribute modifier** — it auto-assigns to `src` or `href` based on tag. No explicit `src=`/`href=` needed:

```gox
<img (doors.ResourceFS(assets, "assets/chart.png"))>          // auto-assigns src
<img (doors.ResourceFS(assets, "assets/chart.png")) type="image/svg+xml">  // + content type
<img (doors.ResourceFS(assets, "assets/logo.png")) cache>     // + cache
<a (doors.ResourceBytes(pdf)) name="report.pdf">Download</a>  // auto-assigns href
```

Shorthands (plain `[]byte`/func) need explicit `src=`/`href=`:
```gox
<img src=(pngBytes)>
<a href=(pdfBytes) name="report.pdf">Download</a>
```

## Cache

Default caching behavior differs by resource type:

| Resource type | Default | Make public/cached | Make private/uncached |
|---------------|---------|---------------------|----------------------|
| Generic (`img`, `a`, etc.) | Private, instance-scoped | `cache` | (already default) |
| Stylesheets (`<style>`, `<link rel="stylesheet">`) | Public, cached | (already default) | `private` or `nocache` |
| Scripts (`<script>`) | Public, cached | (already default) | `private` or `nocache` |

For stylesheets and scripts, `private` and `nocache` both serve through an instance-scoped hook URL; `private` keeps the resource pipeline and shared caching, `nocache` skips shared resource caching. Use `nocache` for content generated per render. Use `private` for static content that should not be publicly reachable. Add `portable` when the URL must load without the session cookie.

For generic resources, add `cache` for stable public content:

```gox
<img (doors.ResourceFS(assets, "assets/logo.png")) cache>
```

- URL becomes hash-based and publicly reachable
- Entry stored in RAM (not for large files)
- Only works with `ResourceFS`, `ResourceLocalFS`, `ResourceBytes`, `ResourceString`, raw `[]byte`
- Handler/hook/proxy sources are always served through a hook: `private` is accepted and changes nothing; they do not take `cache` or `nocache`. String inputs can't use `cache`

Stylesheet and script resources are public and cacheable by default — no `cache` attribute needed. Use `private` to make them instance-scoped. Use `nocache` for dynamically generated content that should not use shared resource caching.

## URL in Code

`doors.NewResource(ctx, resource, contentType) (string, error)` returns the cached URL (the one `cache` produces) with no attribute, for JS that loads the file itself:
```gox
<script data:styles=({
    url, _ := doors.NewResource(ctx, doors.ResourceBytes(widgetCSS), "text/css")
    return url
})>
    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = $data("styles")
    document.head.append(link)
</script>
```
- Set `contentType` for JS/CSS; empty means detection, which gives `text/plain` for them
- Add a file name after a dot: `url + ".widget.css"`
- The error comes only from reading the resource (e.g. a missing file)

## Portable

`portable` gives the URL its own access, so it works without the session cookie (Android WebView downloads, in-app browsers):
```gox
<a href=(doors.ResourceHook(serveReport)) portable name="report.pdf" download>Download report</a>
```
- Bearer link: anyone holding the URL can load it
- Lives while the rendering content lives; stops when that content is cleared, the instance or session ends, or a one-shot hook returns `true`
- Requests need no cookie and create no session; the handler still sees the page's session, the stripped `r.URL.Path` and `Doors-Hook-Prefix`
- Works with `private`/`nocache`; on handler/hook/proxy sources no other attr is needed; `portable` + `cache` is an error

## Content Type

```gox
<img (doors.ResourceFS(assets, "assets/chart.svg")) type="image/svg+xml">
```

## Name

Readable filename in generated URL:
```gox
<a (doors.ResourceBytes(reportPDF)) name="report.pdf">Download</a>
```

For generated downloads, use a fixed or sanitized `name`; do not echo uploaded filenames directly. If the exact response type matters, set `type` on managed generic resources or use `ResourceHandler`/`ResourceHook` and set `Content-Type` yourself. Instance-private resources are the default; use `cache` only for stable public content.

## ResourceExternal

Direct browser URL. `doors.ResourceExternal("https://...")` is a Go type conversion, not a constructor function. When the tag is rendered with the page, it also adds the exact URL to CSP: `script-src` for `<script>` and `modulepreload` links, `style-src` for stylesheet links. Later updates add nothing; see CSP in [configuration.md](./21-configuration.md):
```gox
<link href=(doors.ResourceExternal("https://cdn.example.com/app.css")) rel="stylesheet">
```

For generic images, anchors, iframes, and other `src`/`href` uses, configure the matching CSP directive (`ImgSources`, `FrameSources`, etc.) yourself when needed.

## Custom Endpoints

`url, _ := doors.NewHook(ctx, doors.ResourceHandler(mux.ServeHTTP))` gives browser code its own HTTP endpoint (island API, `EventSource`, `WebSocket`, third-party widget). `false` only means the content is already cleared; safe to ignore.

Requests:
- Returned path has no trailing slash; append `/users/42`, `?q=1`
- Handler sees the part after the endpoint as `r.URL.Path`, always starting with `/` (`url` and `url/` both give `/`); escaped segments stay in `r.URL.RawPath`, query kept, `r.RequestURI` is the original
- `Doors-Hook-Prefix` request header = endpoint path
- Any method; requests run concurrently, so synchronize shared state yourself
- `doors.WithValue` values are on `r.Context()`. Use `ResourceHook` when you need the Doors `ctx`; return `true` to remove the endpoint after that request

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
    <script data:api=({
        url, _ := doors.NewHook(ctx, doors.ResourceHandler(d.api().ServeHTTP))
        return url
    })>
        const { mount } = await import("dashboard")
        mount(document.getElementById("app"), $data("api"))
    </script>
}
```
- Register the module in the head: the import map ships with the page, so `import("dashboard")` works when the island first appears in a later update
- `d.api()` returns one `http.ServeMux` routing sub-paths (`"GET /users/{id}"`); client calls `${api}/users`
- Same-origin, so `fetch` sends the session cookie and default CSP allows it

Use `$hook` (`AHook`/`ARawHook`) to enhance page logic; use a custom endpoint when the client brings its own code and speaks plain HTTP. For static files the client loads, use `doors.NewResource` (URL in Code).

## Related

- [javascript.md](./15-javascript.md) — Script-specific resources
- [styles.md](./16-styles.md) — Stylesheet-specific resources
- [app.md](./04-app.md) — `UseResource` for fixed public paths
