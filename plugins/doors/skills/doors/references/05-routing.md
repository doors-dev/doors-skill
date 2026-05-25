# Routing

URL is reactive state in Doors. Routing = branching content on `doors.Source[doors.Location]`.

Path models (structs with `path:"..."` tags) are the recommended way to do routing, but they are not a framework-enforced requirement. You can route directly on `Location` using the same state routing primitives (`RouteMatch`, `RouteDerive`, etc.) without a path model, or implement a fully custom routing system on top of `doors.Router(ctx)`. See the "Source/Beam-Level Routing" section below for the primitive API.

## Quick Shape

```gox
type Path struct {
    Section Section `path:"/ | /docs/:ID? | /tutorial/:ID? | /license"`
    ID      *string
}

type Section int
const (
    SectionHome Section = iota
    SectionDocs
    SectionTutorial
    SectionLicense
)

elem (a App) Main() {
    <!doctype html>
    <html lang="en">
        <body>
            ~(doors.Route(
                doors.RouteModel(elem(p doors.Source[Path]) {
                    ~(Page(p))
                }),
                doors.RouteLocationDefaultComp(NotFound{}),
            ))
        </body>
    </html>
}
```

## Key Types

```go
type Location struct {
    Segments []string
    Query    url.Values
}
```

## Path Models

A Go struct describing URL shape. Decodes URL -> typed value, encodes back for links/redirects.

### Int Multi-Variant (single field with `|`)

```go
type Path struct {
    Section Section `path:"/ | /docs | /guide"`
}
```
The `int` field stores the matched pattern index. Use with `iota` constants.

### Bool Variants (one field per pattern)

```go
type Path struct {
    Home  bool `path:"/"`
    Docs  bool `path:"/docs"`
    Guide bool `path:"/guide"`
}
```
Matched variant's field becomes `true`. When encoding, first `true` variant in field order wins.

### Choosing: Int vs Bool

- **Int** — compact for many variants, exhaustive switches via `iota` constants, implicit order
- **Bool** — explicit names (`Path{Docs: true}`), natural for ≤3 variants, single-pattern models

### Normalization

- Slashes: `"/docs"`, `"docs"`, `"/docs/"` all equivalent
- Separators: `"/|/docs|/guide"` same as `"/ | /docs | /guide"`
- Cannot mix int and bool variants in one struct

### Params (path segments)

```go
type Path struct {
    Post bool `path:"/posts/:ID"`
    ID   int
}
```
Types: `string`, `int`, `int64`, `uint`, `uint64`, `float64`.

### Optional (`?`)

```go
type Path struct {
    Catalog bool `path:"/catalog/:ID?"`
    ID      *int  // must be pointer
}
```

### Tail (`+` or `*`)

```go
type Path struct {
    Docs bool     `path:"/docs/:Rest+"`
    Rest []string // must be []string
}
```

`+` = required, `*` (or `+?`) = optional. Must be the last segment.

Rules:

- Optional captures must be the last segment
- Multi-segment captures must be the last segment
- `+` and `*` require a `[]string` field
- Required single-segment captures must use non-pointer fields

### Query Params

```go
type Path struct {
    Catalog bool     `path:"/catalog"`
    Color   []string `query:"color"`
    Page    *int     `query:"page"`
}
```
Uses [go-playground/form v4](https://github.com/go-playground/form/tree/v4.2.1) with `query` tag in explicit mode. Pointer = optional (nil when absent).

### Raw Query

```go
type Path struct {
    Search bool       `path:"/search"`
    Query  url.Values // all query values as-is
}
```
Don't mix `url.Values` field with `query` tags.

## Route Builders

### Top-Level

```go
func Route(routes ...RouteSource[Location]) gox.EditorComp         // writable routes for current URL
func RouteModel[M any, C gox.Comp](render func(Source[M]) C) RouteSource[Location]  // decode URL into model
func RouteModelBeam[M any, C gox.Comp](render func(Beam[M]) C) RouteBeam[Location] // read-only model route
```

### Fallbacks

```go
func RouteLocationDefault[C gox.Comp](render func(Source[Location]) C) RouteSource[Location]
func RouteLocationDefaultComp(comp gox.Comp) RouteBeam[Location]
func RouteLocationDefaultBeam[C gox.Comp](render func(Beam[Location]) C) RouteBeam[Location]
```

### Source/Beam-Level Routing

For routing on any `Source[T]` or `Beam[T]` (not just `Location`):

```go
source.Route(routes ...RouteSource[T]) gox.EditorComp
beam.RouteBeam(routes ...RouteBeam[T]) gox.EditorComp
```

**Match builders** (in order: general -> specific):
```go
func RouteDerive[T1 any, T2 comparable](derive func(T1) (T2, bool)) DeriveRoute[T1, T2]
func RouteDeriveEqual[T1 any, T2 any](derive func(T1) (T2, bool), equal func(T2, T2) bool) DeriveRoute[T1, T2]
func RouteMatch[T any](pred func(T) bool) MatchRoute[T]
func RouteValue[T comparable](v T) MatchRoute[T]    // sugar for RouteMatch(== v)
```

**Render methods** on matchers:
```go
// MatchRoute
func (m MatchRoute[T]) Comp(comp gox.Comp) RouteBeam[T]
func (m MatchRoute[T]) Beam(render func(Beam[T]) gox.Elem) RouteBeam[T]
func (m MatchRoute[T]) Source(render func(Source[T]) gox.Elem) RouteSource[T]

// DeriveRoute
func (r DeriveRoute[T1, T2]) Beam(render func(Beam[T2]) gox.Elem) RouteBeam[T1]
func (r DeriveRoute[T1, T2]) Source(set func(T1, T2) T1, render func(Source[T2]) gox.Elem) RouteSource[T1]
```

**Default fallbacks:**
```go
func RouteDefaultComp[T any](comp gox.Comp) RouteBeam[T]
func RouteDefault[T any, C gox.Comp](render func(Source[T]) C) RouteSource[T]
func RouteDefaultBeam[T any, C gox.Comp](render func(Beam[T]) C) RouteBeam[T]
```

## Direct Location Access

```go
func Router(ctx context.Context) Source[Location]  // current URL as writable source
```

`Location` contains reference types (`Segments []string`, `Query url.Values`). Don't mutate — clone first:
```go
loc := doors.Router(ctx).Get().Clone()
```

## URL Building

```go
func NewLocation(model any) (Location, error)    // model = path model, Location, or LocationEncoder
```

```go
type LocationEncoder interface {
    Encode() (Location, error)
}
```

## Multiple Models

List in order of specificity — first match wins:
```gox
~(doors.Route(
    doors.RouteModel(renderHome),
    doors.RouteModel(renderPost),
    doors.RouteModel(renderCatalog),
    doors.RouteLocationDefaultComp(NotFound{}),
))
```

## Security Rules

- URL is client input. A successful match means "URL parses", not "authorized".
- Check permissions while rendering against the current location/decoded model.
- Don't store auth/role in the route. Use session-scoped sources.

## Related

- [navigation.md](./10-navigation.md) — `ALink`, programmatic navigation
- [state.md](./06-state.md) — `Route`, `RouteBeam`, derivation
- [storage-auth.md](./18-storage-auth.md) — Auth pattern
