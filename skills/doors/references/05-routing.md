# Routing

URL is reactive state in Doors. Routing = branching content on `doors.Source[doors.Location]`.

Path models are the normal way to do app routing. They decode URLs into typed Go values and encode those values back into URLs. Routes are leaves (render content) and groups (choose between the routes inside them); groups nest, and one `Route` call renders one container however deep. The same leaves and groups route directly on `Location` without a path model, or on any `Source`/`Beam`; you can also build a custom routing system on top of `doors.Router(ctx)`. See [Route Builders](#route-builders) and [Source/Beam-Level Routing](#sourcebeam-level-routing).

## Contents

- [Quick Shape](#quick-shape)
- [Key Types](#key-types)
- [Path Models](#path-models)
- [Route Builders](#route-builders)
- [Direct Location Access](#direct-location-access)
- [URL Building](#url-building)
- [Multiple Models](#multiple-models)
- [Security Rules](#security-rules)
- [Related](#related)

## Quick Shape

```gox
type Path struct {
    Section Section `/:" | docs/:ID? | tutorial/:ID? | license"`
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
                doors.RouteModel[Path](
                    doors.RouteMatch(func(p Path) bool { return p.Section == SectionHome }, doors.RouteComp[Path](Home{})),
                    doors.RouteMatch(func(p Path) bool { return p.Section == SectionDocs }, doors.RouteBind(DocsPage)),
                    doors.RouteMatch(func(p Path) bool { return p.Section == SectionTutorial }, doors.RouteBind(TutorialPage)),
                    doors.RouteMatch(func(p Path) bool { return p.Section == SectionLicense }, doors.RouteComp[Path](License{})),
                ),
                doors.RouteComp[doors.Location](NotFound{}),
            ))
        </body>
    </html>
}
```

`RouteModel[Path]` matches when the URL decodes into `Path`; the routes inside work on the decoded value. `NotFound` is a leaf, so it always matches and goes last: it catches URLs that do not decode and URLs that decode but match nothing inside the model route.

## Key Types

```go
type Location struct {
    Segments []string   `json:"segments"`
    Query    url.Values `json:"query"`
}
```

`Location` marshals to JSON with `segments`/`query` keys; nil `Segments`/`Query` encode as `[]`/`{}`, not `null`.

## Path Models

A Go struct describing URL shape. Decodes URL -> typed value, encodes back for links/redirects.

Path models use one `int` variant field. Use a named `int` type with `iota` constants for readable route switches.

```go
type Path struct {
    Section Section `/:" | docs | guide"`
}

type Section int
const (
    SectionHome Section = iota
    SectionDocs
    SectionGuide
)
```

The `int` field stores the matched variant index. Encoding picks the variant at that index.

The tag key is the path prefix. The tag value is a `|`-separated list of variants under that prefix.

Use `/` for small models and single pages:

```go
type Path struct {
    Section Section `/:" | catalog | search"`
}
```

Use a longer prefix key to describe an area with several local variants or shared parameters:

```go
type Path struct {
    Section Section `/posts:" | new | archived"`
}
```

This matches `/posts`, `/posts/new`, and `/posts/archived`.

In a real app with dozens of pages, path models stay ergonomic when they are small. Put as much shared path as the area needs in the key, then keep the variants relative to it. For example, `"/post/:ID":"view | edit"` reads as "inside a post, choose view or edit". A larger app might use a deeper key such as `"/org/:OrgID/project/:ProjectID":"overview | settings | ..."`.

Prefer `/:"catalog"` over `/catalog:""` for a single route. A segment in the key is for declaring an area, not for spelling every path segment.

Use `/` as the root prefix:

```go
type Path struct {
    Section Section `/:" | docs | guide"`
}
```

Quote the tag key when the prefix contains `:` or another character that cannot appear in an unquoted Go struct-tag key:

```go
type Path struct {
    Section Section `"/post/:ID":"view | edit"`
    ID      int
}
```

This matches `/post/42/view` and `/post/42/edit`.

### Old API To Convert

Old path models may use bool marker fields or `path:"..."` tags, for example:

```go
type OldPath struct {
    Home bool `path:"/"`
    Docs bool `path:"/docs"`
}

type OldIntPath struct {
    Section Section `path:"/ | /docs | /guide"`
}
```

Treat this as compatibility syntax. In old tags, `path` is used as the tag key instead of a path prefix key such as `/`, `/posts`, or `"/post/:ID"`. When editing routing, docs, examples, or nearby code, convert old bool markers and old `path:"..."` tags to the int variant prefix-tag form unless the user explicitly asks for a compatibility-only edit.

### Normalization

- Write prefixes with a leading slash. Slashes are normalized — `/docs`, `docs`, and `/docs/` describe the same prefix or variant.
- Separators: `"|docs|guide"` same as `" | docs | guide"`.
- Empty variant means the prefix itself: `/posts:" | new"` matches `/posts` and `/posts/new`.

> **Pitfall**: Keep path models to ≤6 route variants. If you need more, split into separate smaller models by area.

### Params (path segments)

```go
type Path struct {
    Section Section `/:"posts/:ID"`
    ID      int
}
```
Types: `string`, `int`, `int64`, `uint`, `uint64`, `float64`.

### Optional (`?`)

```go
type Path struct {
    Section Section `/:"catalog/:ID?"`
    ID      *int // must be pointer
}
```

### Tail (`+` or `*`)

```go
type Path struct {
    Section Section `/:"docs/:Rest+"`
    Rest    []string // must be []string
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
    Section Section `/:"catalog"`
    Color   []string `query:"color"`
    Page    *int     `query:"page"`
}
```
Uses [go-playground/form v4](https://github.com/go-playground/form) with `query` tag in explicit mode. Pointer = optional (nil when absent).

### Raw Query

```go
type Path struct {
    Section Section `/:"search"`
    Query   url.Values // all query values as-is
}
```
Don't mix `url.Values` field with `query` tags.

## Route Builders

### Top-Level

```go
func Route(routes ...SourceRoute[Location]) gox.Elem                    // writable routes for current URL
func RouteModel[M any](routes ...SourceRoute[M]) SourceRoute[Location]   // decode URL into model, route on it
func RouteBeamModel[M any](routes ...BeamRoute[M]) BeamRoute[Location]   // read-only model route
```

Routes are tried in order, depth first; the first leaf reached wins. A chosen branch rerenders only when a different route should show (`RouteBind` is the exception: it rerenders on every value change). If no route matches, nothing renders.

`RouteModel[M]` matches when the URL decodes into `M` and a route inside matches. A URL that decodes but matches nothing inside falls through to the next sibling, usually the 404 leaf.

### Leaves

Leaves render content and always match. A leaf is the fallback of its list: put it last, routes after it are never tried.

```go
func RouteComp[T any](comp gox.Comp) BeamRoute[T]                          // fixed component; nil renders nothing
func RouteBind[T any](render func(v T) gox.Elem) BeamRoute[T]              // rendered from the value, again on every change
func RouteSource[T any](render func(s Source[T]) gox.Elem) SourceRoute[T]  // receives the writable source
func RouteBeam[T any](render func(b Beam[T]) gox.Elem) BeamRoute[T]        // receives a read-only beam
```

Use `T = doors.Location` for top-level `doors.Route(...)` fallbacks.

- `RouteBind` for small stateless views where rerendering is cheap.
- `RouteSource`/`RouteBeam` when the content holds state (inputs, own sources) or is expensive to render; it renders once per entry and follows later values through its source/beam with `Bind`, `Effect`, or derived values inside.
- `RouteComp[T](nil)` renders nothing for the matched values and stops fall-through to later routes.

`RouteComp` renders the same component value each time its branch is entered — its state persists across switches. To start fresh on each entry, wrap it in an element, `doors.RouteComp[T](<>~(MyComp{})</>)`, or use a value-receiver component that initializes in `Main`. This is a common source of bugs.

### Groups

```go
func RouteMatch[T any](match func(v T) bool, routes ...SourceRoute[T]) SourceRoute[T]                      // pred holds and a child matches
func RouteValue[T any](value T, routes ...SourceRoute[T]) SourceRoute[T]                                   // value equal and a child matches
func RouteDerive[T1, T2 any](derive func(Source[T1]) Source[T2], routes ...SourceRoute[T2]) SourceRoute[T1] // children route on the derived source
```

Read-only twins: `RouteBeamMatch`, `RouteBeamValue`, `RouteBeamDerive` (`func(Beam[T1]) Beam[T2]`), `RouteBeamModel`.

- A group matches when its condition holds and a child matches; otherwise routing moves on to its next sibling. A group with no children never matches.
- A chosen branch stays mounted while the conditions on its path hold, even if an earlier route would now match too; it is not rerendered by updates that keep it chosen. A showing leaf gives way to an earlier route that starts matching.
- `RouteDerive` has no condition of its own; put it inside a `RouteMatch` unless it should take everything that reaches it. The derive function only builds the derived source/beam with `DeriveSource`/`DeriveBeam` (`DeriveSourceEqual`/`DeriveBeamEqual` for a custom comparator); it runs on every render of the container, shown or not. While the derived value stays equal, nothing below is checked or rerendered.
- `RouteValue` compares with the comparator of the source it routes (`==` for `NewSource`, `DeriveSource`, `DeriveBeam`; your function for the `Equal` variants). A source with a nil comparator never matches a `RouteValue`; use `RouteMatch`. Match a route enum, predicate, or derived value, not a whole path model with params or query fields.

### Route Granularity Ladder
Keep one typed path source of truth, but route and subscribe at the narrowest level that owns the concern:

1. **Top level:** `doors.Route(doors.RouteModel[Path](...), doors.RouteComp[doors.Location](NotFound{}))` chooses the path model. If broad state has global effects (auth shell, layout, head/status), handle it at that owner.
2. **Segment/page switch:** inside the model route, `RouteMatch`/`RouteValue` groups with one leaf each. This switch should be minimal.
3. **Branch data:** give a branch `RouteSource` only when it needs to write the path. Otherwise narrow it: `RouteBeamDerive` built from `DeriveBeam` for a read-only smaller route value, `RouteDerive` built from `DeriveSource` only when the child writes that derived value back. Both usually sit inside a `RouteMatch`.
4. **Params/query:** bind or effect params, query, filters, and pagination inside the page fragments that actually render them.

Levels nest in one `Route` call and one container. Use a second `Route` call inside leaf content only when a layout must stay mounted while the routes inside switch; that inner call starts over each time its branch is entered.

`Route` is not just syntactic branching. It subscribes to the routed value but swaps the container only when the chosen route changes. `Bind` and `Effect` rerender on subscribed value changes; derive first when they should react to only one field. Direct path binds are usually not needed for routing.

Avoid this dispatch because it rerenders on every `Path` change, including unrelated query or param updates:

```gox
elem Page(path doors.Source[Path]) {
    ~(path.Bind(elem(p Path) {
        ~(if p.Section == SectionReports {
            ~(ReportsPage{path: path})
        } else {
            ~(HomePage{})
        })
    }))
}
```

Use groups and leaves for the page switch:

```gox
~(doors.Route(
    doors.RouteModel[Path](
        doors.RouteMatch(func(p Path) bool { return p.Section == SectionReports }, doors.RouteSource(ReportsPage)),
        doors.RouteMatch(func(p Path) bool { return p.Section == SectionHome }, doors.RouteComp[Path](HomePage{})),
    ),
    doors.RouteComp[doors.Location](NotFound{}),
))
```

If a branch only needs a derived route value, pass that value instead of the whole path:

```gox
doors.RouteModel[Path](
    doors.RouteBeamMatch(func(p Path) bool { return p.Section == SectionReportDetail },
        doors.RouteBeamDerive(func(path doors.Beam[Path]) doors.Beam[string] {
            return doors.DeriveBeam(path, func(p Path) string { return p.ReportID })
        }, doors.RouteBeam(ReportDetail)),
    ),
    doors.RouteComp[Path](ReportsIndex{}),
),
```

Use the writable `RouteDerive` with `DeriveSource` only when the child must write the derived value back into the parent path model; otherwise `RouteBeamDerive`.

### Source/Beam-Level Routing

For routing on any `Source[T]` or `Beam[T]` (not just `Location`), with the same leaves and groups:

```go
source.Route(routes ...SourceRoute[T]) gox.Elem   // writable tree
beam.RouteBeam(routes ...BeamRoute[T]) gox.Elem   // read-only tree
```

`BeamRoute[T]` routes are accepted wherever `SourceRoute[T]` is. `RouteSource` and the writable groups (`RouteMatch`, `RouteValue`, `RouteDerive`, `RouteModel`) fit only under `Route` and other writable groups; a read-only group inside a `Route` tree makes its own subtree read-only. Don't confuse the method `x.RouteBeam(routes...)`, which starts a read-only tree, with the leaf `doors.RouteBeam(render)`, which fits in any tree.

## Direct Location Access

```go
func Router(ctx context.Context) Source[Location]  // current URL as writable source
```

`ctx` must belong to a Doors render or handler; otherwise `Router` panics. Updates to a location with the same path and query are suppressed.

`Location` contains reference types (`Segments []string`, `Query url.Values`). Don't mutate — clone first:
```go
loc := doors.Router(ctx).Get().Clone()
```

### Mutating location in the page factory

You can redirect or adjust the initial URL by mutating `doors.Router(ctx)` in the page function passed to `doors.NewApp`. The browser URL is replaced and the app observes the new location as the initial state:
```go
app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
    doors.Router(ctx).Update(ctx, doors.Location{Segments: []string{"login"}})
    return App{}
})
```

**Important:** To read the current location before deciding whether to redirect, use `Get()` — unlike `Read`, it does not freeze the observable value for the render cycle. Place any `Sub` or `ReadAndSub` calls **after** the mutation.

## URL Building

```go
func NewLocation(model any) (Location, error)    // model = path model, Location, or LocationEncoder
```

```go
type LocationEncoder interface {
    Encode() (Location, error)
}
```

Error sentinels, matched with `errors.Is`: `ErrPathModel` = invalid path model definition (bad tags, wrong field types, unexported fields); `ErrPathEncode` = model failed to encode into a location (no variant selected, empty required capture). Returned by `NewLocation` and wrapped by location actions / `ALink` model encoding.

## Multiple Models

List in order of specificity — the first model that decodes the URL and has a matching route inside wins:
```gox
~(doors.Route(
    doors.RouteModel[HomePath](doors.RouteComp[HomePath](Home{})),
    doors.RouteModel[PostPath](doors.RouteBind(PostPage)),
    doors.RouteModel[CatalogPath](doors.RouteSource(Catalog)),
    doors.RouteComp[doors.Location](NotFound{}),
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
