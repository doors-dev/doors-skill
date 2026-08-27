# Navigation

In-app navigation without full page reload.

> **Important**: Do not use raw `href` on `<a>` elements for in-app navigation — always use `doors.ALink` to avoid full page reloads.

## ALink

Declarative navigation on `<a>` elements:

```gox
~>doors.ALink{
    Model: Path{Section: SectionHome},
} <a>Home</a>
```

### Fields

```go
Model    // required: path model, Location, or LocationEncoder
Fragment // optional: #hash appended to URL, scrolled into view after successful navigation
Active   // optional: rules for applying active-link indication
StopPropagation // optional: stop the click event from bubbling
HistoryReplace  // optional: replace current history entry instead of pushing a new one
After    // optional: actions after successful navigation (ALink-specific field)
// + all shared event lifecycle fields: Scope, Indicator, Before, OnError
```

All links share one built-in latest scope, so a new click cancels a pending navigation. `OnError` has no default — a failed navigation reverts the optimistic URL change (v0.14 defaulted nil `OnError` to `ActionLocationReload{}`; it no longer does).

### Behavior

- Click intercepted → hook updates location source → page re-routes in place
- ALink always navigates dynamically on normal clicks
- A click that changes neither path nor query sends no request
- `href` set from encoded model (for browser features: middle-click, Cmd-click, "open in new tab")
- Opening in a new tab is a fresh initial request, like any other direct page load
- Client updates browser URL to link `href` before hook runs

### Failure Semantics

- Canceled (by scope) or 404 (hook removed): URL reverts silently, `OnError` does not run
- Gone 410 (instance stopped): page reloads at the new URL, `OnError` does not run
- Network error or 5xx: URL reverts, `OnError` runs
- 400 or other unexpected errors: URL stays at the new path, `OnError` runs

## Programmatic Navigation

Update the `Source` received from `RouteModel`:

```go
// Replace entirely
path.Update(ctx, Path{Section: SectionDashboard, ID: cityID})

// Modify in place
path.Mutate(ctx, func(p Path) Path {
    p.Section = SectionDashboard
    return p
})
```

Or update the raw location directly:

```go
doors.Router(ctx).Update(ctx, newLocation)
```

`Update`/`Mutate` return `<-chan error`; ignore for fire-and-forget.

### History Replace

A programmatic update pushes a new history entry by default. To replace the current entry instead, wrap the context:

```go
path.Update(doors.HistoryReplaceContext(ctx), Path{Section: SectionDashboard})
```

Honored on the `Router` source and any source derived from it (e.g. a `RouteModel` source); no effect on other sources. For links, use the `ALink.HistoryReplace` field.

## Active Link

```go
type Active struct {
    Indicator     Indicators       // applied when current location matches
    PathMatcher   PathMatcher      // how path is compared
    QueryMatcher  QueryMatcher     // how query is compared
    FragmentMatch bool             // include #... in matching
}
```

### Path Matchers

```go
func PathMatcherFull() PathMatcher           // full path match (default)
func PathMatcherStarts() PathMatcher          // current path starts with link path
func PathMatcherSegments(i ...int) PathMatcher // only listed segment indexes
```

### Query Matchers

Matchers run **sequentially** — each step processes a subset of query parameters, then passes the rest to the next step. After the chain, any remaining parameters are compared directly.

Chain with `.And(...)`:

```go
func QueryMatcherSome(params ...string) QueryMatcher         // compare only these keys at this step
func QueryMatcherIgnoreSome(params ...string) QueryMatcher   // exclude these keys from further comparison
func QueryMatcherIgnoreAll() QueryMatcher                    // exclude all remaining keys
func QueryMatcherIfPresent(params ...string) QueryMatcher    // compare only when the key is present
```

This sequential model covers many scenarios. For example:

```gox
// Only "mode" matters; ignore everything else
QueryMatcher: doors.QueryMatcherSome("mode").And(doors.QueryMatcherIgnoreAll()),

// "category" must match; all other params must also match
QueryMatcher: doors.QueryMatcherSome("category"),
// (no IgnoreAll — remaining params are compared directly)

// "page" must match if present; ignore everything else
QueryMatcher: doors.QueryMatcherIfPresent("page").And(doors.QueryMatcherIgnoreAll()),
```

## LocationEncoder

Custom types that encode themselves:

```go
type LocationEncoder interface {
    Encode() (Location, error)
}
```

Works wherever `Model` is accepted (`ALink`, `ActionLocationAssign`, `ActionLocationReplace`, `NewLocation`).

## Hard Navigation (Actions)

Full page loads that bypass the Doors runtime. Use only when you intentionally need a full browser navigation — e.g., redirecting to an external site, or recovering from a fatal error. For normal in-app navigation after form submissions or user actions, update the route source instead.

```go
doors.ActionLocationReload{}                              // reload current page
doors.ActionLocationAssign{Model: path}                   // push + load
doors.ActionLocationReplace{Model: path}                  // replace + load
doors.ActionLocationRawAssign{URL: "https://..."}         // literal URL, push
doors.ActionLocationRawReplace{URL: "https://..."}        // literal URL, replace history entry
```

## Related

- [routing.md](./05-routing.md) — Path models, `RouteModel`, `Route`
- [indication.md](./12-indication.md) — `Indicator` on ALink
- [actions.md](./13-actions.md) — Location actions
