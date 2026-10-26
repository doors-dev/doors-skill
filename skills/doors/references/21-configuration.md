# Configuration

App-level options passed to `doors.NewApp(page, options...)`.

## Options

```go
func WithConf(conf Conf) With                            // runtime, session, serving
func WithCSP(csp CSP) With                               // Content Security Policy
func WithID(id string) With                              // server ID (URL prefix + cookie name)
func WithIDCookie(name string) With                      // sticky-session cookie (empty = off)
func WithLogger(l *slog.Logger) With                     // internal logger; doors.Logger(ctx) reads it back (default slog.Default())
func WithSessionTracker(t SessionTracker) With           // observe session create/delete; repeatable, run in registration order
func WithErrorPage(ep ErrorPage) With                    // custom error page
func WithESProfiles(f func(string) api.BuildOptions) With // esbuild profiles
func WithPrinter(p func(next gox.Printer) gox.Printer) With // wrap the HTML output printer
func WithValue(key, value any) With                      // ctx.Value(key) in every Doors ctx and request
func WithFunc(f func() With) With                        // build an option once per app, in NewApp
```

`ESProfile{...}` also implements `With`.

## Conf fields

```go
type Conf struct {
    SessionInstanceLimit      int           // max live instances per session; above it least active is suspended (default 12)
    SessionTTL                time.Duration // session lifetime after last request; raised to at least InstanceTTL
    InstanceConnectTimeout    time.Duration // rendered page connect-back deadline (default RequestTimeout)
    InstanceTTL               time.Duration // disconnected instance lifetime (default 40m; never below 2*RequestTimeout)
    InstanceGoroutineLimit    int           // max render/reactive goroutines per instance (default 8)
    DisconnectHiddenTimer     time.Duration // hidden page pause delay; reconnects when visible (default InstanceTTL/2)
    RequestTimeout            time.Duration // one-request limit: server page render, browser hook/navigation requests (default 30s)

    ServerCacheControl            string // managed resource cache header (default: immutable 1y)
    ServerDisableGzip             bool   // no gzip for HTML, managed resources
    ServerDisableHead             bool   // page HEAD answers 405; default renders the page for status + headers, no body (static files/resources always answer HEAD)
    ServerSessionCookiePrefix     string // prepended to session cookie name (e.g. __Host-)
    ServerSessionCookieNoSecure   bool   // omit Secure (dev only)
    ServerRequestBodyLimit        int    // max hook/form request body bytes (default 8 MB); per-request override via r.SetRequestBodyLimit

    // Solitaire transport tuning (rarely needed)
    SolitaireRollTime               time.Duration // max live connection request lifetime before rolling (default 15s)
    SolitaireSyncTimeout            time.Duration // max wait for browser ack before ending instance (default InstanceTTL, capped at it)
    SolitaireFrameTime              time.Duration // max frame buffer time before flush (default ~33ms)
    SolitaireFrameSize              int           // max frame buffer bytes before flush (default 32 KB)
    SolitaireDisableGzip            bool          // no gzip for door updates and action payloads
    SolitaireQueue                  int           // max updates awaiting delivery or ack; exceeding ends instance (default 1024)
    SolitairePending                int           // max delivered-but-unacked updates; at limit sending pauses (default 256); also bounds the calls batches hold in the browser, at the limit the oldest batch is applied early
    SolitaireDisableReportStreaming bool          // browser posts each message separately (auto fallback outside HTTP/2/3)
    SolitaireReportLimit            int           // max browser message size (default 8 MB)
    SolitaireReportTimeout          time.Duration // max time to receive one message (default min(5s, RollTime))
    SolitaireMaxRTT                 time.Duration // RTT estimate cap; raised to at least 2*FrameTime (default 1s)
}
```

`AHook`, `ARawHook`, `ASubmit`, `ARawSubmit` carry a `RequestTimeout time.Duration` field overriding `Conf.RequestTimeout` per hook.

## CSP

CSP off until `WithCSP` is called:

```go
type CSP struct {
    ScriptSources         []string   // append to 'self' + import map hash (if any) + external script URLs
    StyleSources          []string   // append to 'self' + external stylesheet URLs
    ConnectSources        []string   // append to 'self'
    DefaultSources        []string   // nil='self', []=omit, values=emit
    FormActions           []string   // default 'none', []=omit
    ObjectSources         []string   // default 'none', []=omit
    FrameSources          []string   // default 'none', []=omit
    FrameAncestors        []string   // default 'none', []=omit
    BaseURIAllow          []string   // default 'none', []=omit
    ImgSources            []string   // []=omit
    FontSources           []string   // []=omit
    MediaSources          []string   // []=omit
    Sandbox               []string   // []=omit
    WorkerSources         []string   // []=omit
    ReportTo              string     // only emits report-to directive
}
```

Managed scripts and stylesheets (incl. plain inline `<script>`/`<style>`) load from Doors URLs covered by `'self'`.

Add external sources to `ScriptSources`/`StyleSources` yourself when a later update (Door update, `Reload`, deferred content) can render an external script/stylesheet the page did not, or when an external script loads other scripts (e.g. modules it imports). The header is sent once with the page response and holds only the exact external URLs rendered with the page, including every Door placed during it.

Doors ships no stylesheet of its own (the `d0-r` rule is applied via a constructed stylesheet in the blocking head script), so a strict `style-src` needs no Doors resource origin.

`ReportTo` only emits the `report-to` directive. Send the matching `Report-To` response header yourself in the app factory.

| Fields | nil | [] | values |
|--------|-----|-----|--------|
| ScriptSources, StyleSources, ConnectSources | keep Doors defaults only | keep Doors defaults | append your values |
| DefaultSources | emit 'self' | omit directive | emit your values |
| FormActions, ObjectSources, FrameSources, FrameAncestors, BaseURIAllow | default to 'none' | omit directive | emit your values |
| ImgSources, FontSources, MediaSources, Sandbox, WorkerSources | omit directive | omit directive | emit your values |

## Esbuild

```go
type ESProfile struct {
    External []string
    Minify   bool
    JSX      JSX
}

type JSX struct {
    JSX          api.JSX
    Factory      string
    ImportSource string
    Fragment     string
    SideEffects  bool
    Dev          bool
}

func JSXReact() JSX    // automatic runtime
func JSXPreact() JSX   // classic Preact
```

Esbuild profiles apply to the main Doors client bundle (the `""` profile) and managed scripts/modules. Stylesheets are minified by a separate CSS minifier — profiles don't affect them. For named profiles:

```go
doors.WithESProfiles(func(profile string) api.BuildOptions {
    switch profile {
    case "react": return api.BuildOptions{...}
    default:      return api.BuildOptions{...}  // must support ""
    }
})
```

## Server ID

```go
doors.WithID("blue")
```
- Runtime URLs: `/~/blue/...`
- Cookie name: `blue` (with `ServerSessionCookiePrefix` prepended, e.g. `__Host-blue`)

Must be URL-safe (no escaping). Use when running multiple Doors deployments side by side.

```go
doors.WithIDCookie("server_id")
```
Sets an extra cookie carrying the server ID for sticky session load balancers.

## Custom Error Page

```go
doors.WithErrorPage(func(r *http.Request, err error) gox.Elem {
    return ErrorPage(err) // user-defined element
})
```

## Printer Middleware

`WithPrinter(func(next gox.Printer) gox.Printer)` wraps the printer Doors serializes render jobs through — for stripping unwanted attributes, render metrics, output auditing. Nil disables wrapping.

```go
type stripHandlers struct {
    next gox.Printer
}

func (s stripHandlers) Send(j gox.Job) error {
    if open, ok := j.(*gox.JobOpen); ok && open.Attrs != nil {
        for _, attr := range open.Attrs.List() {
            name := attr.Name()
            if attr.IsSet() && len(name) > 2 && strings.EqualFold(name[:2], "on") {
                attr.Unset()
            }
        }
    }
    return s.next.Send(j)
}

app := doors.NewApp(page, doors.WithPrinter(func(next gox.Printer) gox.Printer {
    return stripHandlers{next: next}
}))
```

Contract:

- Called once per **drain**: an initial page render (whole document), or a Door render cycle (updated Door + descendant Doors, one payload).
- Returned printer must be non-nil; it gets that drain's jobs as sequential `Send` calls on one goroutine, in document order, never reused across drains. The middleware func itself may run concurrently — keep per-drain state in the returned printer, not shared vars.
- Jobs are pooled/single-use: forward each to `next` exactly once; never retain a job or its `Attrs` after `Send` returns (`Attrs.Clone` for an independent copy).
- `job.Context()` carries the producing render scope (works with `doors.SessionContext` etc.).
- `gox.JobOpen` attrs are mutable until serialized; may be nil on no-output container heads.
- Do not modify `d0*` elements/attributes or rewritten resource URLs; do not inject head-relevant elements before the document head; do not block (render hot path).
- Not wrapped: `WithErrorPage` output, static files/resources.

## Context Values

```go
type dbKey struct{}

func DB(ctx context.Context) *sql.DB { return ctx.Value(dbKey{}).(*sql.DB) }

app := doors.NewApp(page, doors.WithValue(dbKey{}, db))
```

- Unexported key + typed helper.
- Seen in the page factory, renders, handlers, `DetachedContext`, `InstanceContext`, `SessionContext`, `r.Context()`, and the hook/resource `*http.Request`.
- Same key set inside Doors (`context.WithValue` on a Doors ctx, `doors.Ctx`) wins; same key set by `app.Use` middleware wins on `r.Context()`. Repeated key: last wins. nil/non-comparable key panics in `NewApp`.
- `WithFunc(f)`: f runs once per `NewApp` and its option is applied, so one option shared by several apps gives each app its own value. nil f or nil result: no-op.

```go
func withCache() doors.With {
    return doors.WithFunc(func() doors.With {
        return doors.WithValue(cacheKey{}, newCache())
    })
}
```

## Session Tracker

```go
type SessionTracker interface {
    Create(id string, r *http.Request)   // don't retain request or read body
    Delete(id string)                    // at most once per session
}
```

- `WithSessionTracker` accumulates: repeat it to install several observers; they run in registration order. Nil installs nothing.
- Both methods run inline on the triggering goroutine — must not block.
- Sessions are created lazily on first actual touch of a session API; requests that never touch one (static resources, crawlers) create no session, so `Create` does not fire per request.

## Rules

- Start with defaults, change only what you need
- Turn on CSP with `WithCSP` when you need it, add minimal sources
- `ESProfile` for simple config, `WithESProfiles` for named profiles
- `WithID` for side-by-side deployments
- `WithIDCookie` for sticky session load balancing

## Related

- [app.md](./04-app.md) — App creation, middleware
- [session-instance.md](./19-session-instance.md) — `Conf` lifetime fields in practice
- [javascript.md](./15-javascript.md) — Esbuild profiles applied to scripts
