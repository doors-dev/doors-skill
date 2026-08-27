# App

`doors.App` is the HTTP entry point for a Doors application. It implements `http.Handler`.

## Creation

```go
func NewApp[C gox.Comp](page func(ctx context.Context, r Request) C, options ...With) App
```

The page factory runs once per page instance (each full page load creates one). Use it to:
- Bootstrap session-scoped state from cookies/headers (auth, theme, locale)
- Read request headers, set cookies, set response headers
- Return the root component

Day-to-day routing happens *inside* the returned component, not here.

```go
app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
    auth := doors.SessionStore(ctx).Init(authKey{}, func() any {
        c, err := r.GetCookie("session")
        if err != nil { return doors.NewSource(false) }
        _, ok := store.Get(c.Value)
        return doors.NewSource(ok)
    }).(doors.Source[bool])
    return App{auth: auth}
})
```

## App Interface

```go
type App interface {
    Use(middleware ...Use)
    InstanceCount() int
    SessionCount() int
    Drain(callback func()) // one-way drain mode; callback once when last instance is gone
    http.Handler
}
```

`Drain` stops refreshing the app id cookie and makes in-app navigation end the instance (browser reloads). Use for graceful shutdown/handover.

## Middleware

`app.Use(...)` adds standard `func(http.Handler) http.Handler` middleware. It runs after Doors injects the session context and wraps both Doors system endpoints (`/~/...`) and page rendering. Sessions are lazy: requests that never touch session APIs (static files, crawlers) allocate no session state.

### Static Files

```go
app.Use(doors.UseDir("/assets/",  "./assets",  doors.CacheControlImmutable))
app.Use(doors.UseFS("/static/",   embedFS,     doors.CacheControlStatic))
app.Use(doors.UseFile("/robots.txt", "./static/robots.txt", doors.CacheControlStatic))
```

### Embedded Static Assets

Embed CSS as managed resource (`[]byte` on `href=`) and other static files (images, fonts) via `UseFS`:

```go
// assets/embed.go
//go:embed style.css
var Style []byte
//go:embed static/*
var static embed.FS
func Static() fs.FS { sub, _ := fs.Sub(static, "static"); return sub }
```

```go
app.Use(doors.UseFS("/static", assets.Static(), doors.CacheControlStatic))
```

```gox
<link rel="icon" type="image/png" href="/static/ico.png">
<link href=(assets.Style) rel="stylesheet" name="main.css">
```

### Resource at Fixed Path

```go
app.Use(doors.UseResource("/assets/font.woff2", doors.ResourceFS(fsys, "font.woff2"), "font/woff2"))
```

An empty `contentType` leaves the Content-Type header unset.

### Custom Middleware

```go
app.Use(logger.Handler, cors.New(cors.Options{}).Handler, doors.UseDir(...))
```

Middleware runs in registration order (first registered = outermost). Non-short-circuiting requests fall through to Doors handler.

The request context in middleware carries `SessionContext` values (session-level, not instance-level). See [context.md](./03-context.md) for API compatibility. This is useful for auth bootstrapping — reading cookies and populating `SessionStore` before the handler runs. First touch of a session API is what creates the session.

## Options

```go
type With interface { /* passed to NewApp */ }

func WithConf(conf Conf) With                  // Runtime config
func WithCSP(csp CSP) With                     // Content Security Policy
func WithID(id string) With                    // Server ID for URLs & cookie naming
func WithIDCookie(name string) With            // Sticky-session cookie (empty = off)
func WithLogger(l *slog.Logger) With           // Internal logger; read back via doors.Logger(ctx)
func WithSessionTracker(t SessionTracker) With // Observe session create/delete; repeatable, run in registration order
func WithErrorPage(ep ErrorPage) With          // Custom error page renderer
func WithESProfiles(f func(string) api.BuildOptions) With // esbuild profiles
func WithPrinter(p func(next gox.Printer) gox.Printer) With // Wrap the gox.Printer Doors uses to emit HTML
```

`ESProfile{...}` also implements `With`.

`WithPrinter` wrapper — invoked once per drain (page render or door render cycle incl. descendants); may be invoked concurrently across drains, but each returned printer (must be non-nil) gets sequential `Send` calls on one goroutine. Jobs are pooled: forward each exactly once, never retain a job or its `Attrs` after `Send` returns (`Attrs.Clone` for a copy); `job.Context()` carries the render scope. `gox.JobOpen.Attrs` mutable until serialized (may be nil on no-output container heads). Do not touch `d0*`-managed output or inject head-relevant elements before the document head; do not block. Not wrapped: error pages, failed-cycle replacement HTML, static files/resources. Nil disables wrapping.

## Cache-Control Constants

```go
CacheControlImmutable // public, max-age=31536000, immutable
CacheControlStatic    // public, max-age=3600, must-revalidate
CacheControlStaticShort // public, max-age=300, must-revalidate
CacheControlHTML      // public, max-age=0, must-revalidate
CacheControlCDN       // public, max-age=3600, s-maxage=86400
CacheControlPrivate   // private, max-age=0, must-revalidate
CacheControlNoCache   // no-cache
CacheControlNoStore   // no-store
CacheControlAPI       // private, no-cache
```

## Mounting in Another Server

`doors.App` is a regular `http.Handler`:

```go
mux := http.NewServeMux()
mux.Handle("/admin/", adminHandler)
mux.Handle("/", app)
http.ListenAndServe(":8080", mux)
```

## Related

- [get-started.md](./01-get-started.md) — Minimal project setup
- [routing.md](./05-routing.md) — Routing inside components
- [storage-auth.md](./18-storage-auth.md) — Auth bootstrap pattern
- [configuration.md](./21-configuration.md) — All `Conf` fields
