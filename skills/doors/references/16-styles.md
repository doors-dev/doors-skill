# Styles

Class helpers + stylesheet resources.

## Class Helper

```go
func Class(classes ...string) Classes
```

```gox
var card = doors.Class("rounded-xl border p-4", "bg-white shadow-sm")
```

Each argument split by `strings.Fields` — `Class("a b")` = `Class("a", "b")`.

### Methods (immutable — return new value)

```go
func (c Classes) Add(classes ...string) Classes      // append classes
func (c Classes) Remove(classes ...string) Classes    // remove currently-added classes
func (c Classes) Filter(classes ...string) Classes    // omit classes from output (persistent)
func (c Classes) Join(classes ...Classes) Classes     // combine added + filtered
func (c Classes) Clone() Classes                      // independent copy
func (c Classes) String() string                      // rendered class string
```

### Usage Forms

```gox
// As attribute value
<div class=(card)>...</div>

// As attribute modifier
<div class="p-4" (doors.Class("rounded-lg"))>...</div>

// As element proxy
~>(doors.Class("h-5 w-5")) ~(Icon())
```

`Filter` vs `Remove`:
- `Remove` only removes currently-added classes (can be re-added later)
- `Filter` persistently omits classes from output (even if added later or via Join)

Tailwind note: Doors does not run Tailwind generation. Keep the project's Tailwind/PostCSS/CSS build configured separately, and make sure it scans `.gox`/`.go` sources or safelists classes assembled in Go.

Stylesheet resources are **public and cacheable by default** (hash-based URL, minified). No `cache` attribute needed — unlike generic resources which are private by default. `private` serves through an instance-scoped hook URL while still using the stylesheet pipeline (cached, reused). `nocache` serves through an instance-scoped hook URL without shared resource caching (new resource per call). Use `nocache` for dynamically generated styles; use `private` when the content is static but should not be publicly reachable.

### Plain inline `<style>` (auto-managed)

```gox
<style>
    h1 { color: red; }
</style>
```
By default Doors collects CSS → creates stylesheet resource → emits `<link rel="stylesheet">`. Use `raw` to keep literal `<style>` tag.

### Embedded CSS

Embed the stylesheet at compile time, serve as a managed resource with hash-based caching:

```go
//go:embed style.css
var Style []byte
```

```gox
<link href=(Style) rel="stylesheet" name="main.css">
```

Doors turns the `[]byte` into a cacheable URL. `name` gives the generated file a readable filename.

### Stylesheet Sources

```go
doors.ResourceLocalFS("web/app.css")
doors.ResourceFS(webFS, "app.css")
doors.ResourceBytes(appCSS)
doors.ResourceString(appCSS)
doors.ResourceExternal("https://cdn.example.com/app.css") // direct external URL
```

Shorthand: `href=(appCSS)` where `appCSS` is `[]byte` is equivalent to `href=(doors.ResourceBytes(appCSS))`. Same for handler functions.

For full resource behavior (caching, content type, name, private/nocache), see [resources.md](./14-resources.md).

### Attrs

| Attr | Effect |
|------|--------|
| `raw` | Keep literal `<style>` tag or raw link |
| `name="..."` | Readable output filename |
| `private` | Instance-scoped URL |
| `nocache` | No shared resource caching (for dynamically generated styles) |

`name`, `private`, and `nocache` also work on managed `<style>...</style>` tags; `raw` keeps the literal style tag instead of turning it into a stylesheet resource.

## Related

- [resources.md](./14-resources.md) — Generic resource syntax
- [javascript.md](./15-javascript.md) — Script resources
