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
func NewHook(ctx context.Context, r Resource) (string, bool)  // register resource as hook; body NOT bounded by ServerRequestBodyLimit
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

For stylesheets and scripts, `private` and `nocache` both serve through an instance-scoped hook URL — they are the same property. Use `nocache` when the content is dynamically generated and changes between renders. Use `private` when the content is static but should not be publicly reachable.

For generic resources, add `cache` for stable public content:

```gox
<img (doors.ResourceFS(assets, "assets/logo.png")) cache>
```

- URL becomes hash-based and publicly reachable
- Entry stored in RAM (not for large files)
- Only works with `ResourceFS`, `ResourceLocalFS`, `ResourceBytes`, `ResourceString`, raw `[]byte`
- Handler/hook/proxy/string inputs can't use `cache`

Stylesheet and script resources are public and cacheable by default — no `cache` attribute needed. Use `private` to make them instance-scoped. Use `nocache` for dynamically generated content that should not use shared resource caching.

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

Direct browser URL. `doors.ResourceExternal("https://...")` is a Go type conversion, not a constructor function. For script and stylesheet resources, it also registers the URL with `script-src` or `style-src` CSP collection:
```gox
<link href=(doors.ResourceExternal("https://cdn.example.com/app.css")) rel="stylesheet">
```

For generic images, anchors, iframes, and other `src`/`href` uses, configure the matching CSP directive (`ImgSources`, `FrameSources`, etc.) yourself when needed.

## Related

- [javascript.md](./15-javascript.md) — Script-specific resources
- [styles.md](./16-styles.md) — Stylesheet-specific resources
- [app.md](./04-app.md) — `UseResource` for fixed public paths
