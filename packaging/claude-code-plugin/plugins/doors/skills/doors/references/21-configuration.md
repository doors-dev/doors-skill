# Configuration

App-level options passed to `doors.NewApp(page, options...)`.

## Options

```go
func WithConf(conf Conf) With                            // runtime, session, serving
func WithCSP(csp CSP) With                               // Content Security Policy
func WithID(id string) With                              // server ID (URL prefix + cookie name)
func WithLogger(l *slog.Logger) With                     // internal logger
func WithSessionTracker(t SessionTracker) With           // observe session create/delete
func WithErrorPage(ep ErrorPage) With                    // custom error page
func WithESProfiles(f func(string) api.BuildOptions) With // esbuild profiles
```

`ESProfile{...}` also implements `With`.

## Conf fields

```go
type Conf struct {
    SessionInstanceLimit      int           // max instances per session (default 12)
    SessionTTL                time.Duration // session lifetime after activity; raised to at least InstanceTTL
    InstanceConnectTimeout    time.Duration // new instance connection deadline
    InstanceTTL               time.Duration // inactive instance lifetime (default 40m; never below 2*RequestTimeout)
    InstanceGoroutineLimit    int           // max runtime goroutines per instance (default 8)
    DisconnectHiddenTimer     time.Duration // hidden page delay before disconnecting (default InstanceTTL/2)
    RequestTimeout            time.Duration // max event hook request duration (default 30s)

    ServerCacheControl            string // Doors JS/CSS cache header (default: immutable 1y)
    ServerDisableGzip             bool
    ServerSessionCookiePrefix     string // cookie prefix (e.g. __Host-)
    ServerSessionCookieNoSecure   bool   // omit Secure (dev only)
    ServerIDCookieName            string // sticky-session cookie name (empty = off)
    ServerRequestBodyLimit        int    // max request body bytes for hooks/forms; also max memory for ASubmit (default 8 MB)

    // Solitaire transport tuning (rarely needed)
    SolitaireRollTime               time.Duration // max request lifetime before rolling (default 15s)
    SolitaireSyncTimeout            time.Duration // max pending sync task (default InstanceTTL)
    SolitaireFrameTime              time.Duration // max frame buffer time before flush (default ~33ms)
    SolitaireFrameSize              int           // max frame buffer bytes before flush (default 32 KB)
    SolitaireDisableGzip            bool
    SolitaireQueue                  int           // max queued + unresolved sync tasks (default 1024)
    SolitairePending                int           // max unresolved sync tasks (default 256)
    SolitaireDisableReportStreaming bool          // disable browser streaming reports
    SolitaireReportLimit            int           // max report size (default 8 MB)
    SolitaireReportTimeout          time.Duration // max time to receive one report (default min(5s, RollTime))
    SolitaireMaxRTT                 time.Duration // RTT estimate cap for sync probing (default 1s)
}
```

## CSP

CSP off until `WithCSP` is called:

```go
type CSP struct {
    ScriptSources         []string   // append to 'self' + collected hashes
    StyleSources          []string   // append to 'self' + collected hashes
    ConnectSources        []string   // append to 'self'
    DefaultSources        []string   // nil=built-in default, []=omit, values=emit
    FormActions           []string   // default 'none', []=omit
    ObjectSources         []string   // default 'none', []=omit
    FrameSources          []string   // default 'none', []=omit
    FrameAcestors         []string   // default 'none', []=omit
    BaseURIAllow          []string   // default 'none', []=omit
    ImgSources            []string   // []=omit
    FontSources           []string   // []=omit
    MediaSources          []string   // []=omit
    Sandbox               []string   // []=omit
    WorkerSources         []string   // []=omit
    ScriptStrictDynamic   bool
    ReportTo              string     // only emits report-to directive
}
```

Doors auto-collects  `ResourceExternal(...)` sources for script/style resources on initial render.

`ReportTo` only emits the `report-to` directive. Send the matching `Report-To` response header yourself in the app factory.

| Fields | nil | [] | values |
|--------|-----|-----|--------|
| ScriptSources, StyleSources, ConnectSources | keep Doors defaults only | keep Doors defaults | append your values |
| DefaultSources | use built-in default | omit directive | emit your values |
| FormActions, ObjectSources, FrameSources, FrameAcestors, BaseURIAllow | default to 'none' | omit directive | emit your values |
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

Used for main Doors client bundle + managed scripts/stylesheets. For named profiles:

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
- Cookie name: `blue` (by default, overridden by `ServerSessionCookiePrefix`)

Must be URL-safe (no escaping). Use when running multiple Doors deployments side by side.

## Custom Error Page

```go
doors.WithErrorPage(func(r *http.Request, err error) gox.Elem {
    return ErrorPage(err) // user-defined element
})
```

## Session Tracker

```go
type SessionTracker interface {
    Create(id string, r *http.Request)   // don't retain request or read body
    Delete(id string)
}
```

## Rules

- Start with defaults, change only what you need
- Turn on CSP with `WithCSP` when you need it, add minimal sources
- `ESProfile` for simple config, `WithESProfiles` for named profiles
- `WithID` for side-by-side deployments

## Related

- [app.md](./04-app.md) — App creation, middleware
- [session-instance.md](./19-session-instance.md) — `Conf` lifetime fields in practice
- [javascript.md](./15-javascript.md) — Esbuild profiles applied to scripts
