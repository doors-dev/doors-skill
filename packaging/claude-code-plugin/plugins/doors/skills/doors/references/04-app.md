# App

`doors.App` is the HTTP entry point for a Doors application. It implements `http.Handler`.

## Creation

```go
func NewApp[C gox.Comp](page func(ctx context.Context, r Request) C, options ...With) App
```

The page factory runs once per request (new page instance). Use it to:
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
    http.Handler
}
```

## Middleware

`app.Use(...)` adds standard `func(http.Handler) http.Handler` middleware. It runs after internal session initiation and wraps both Doors system endpoints (`/~/...`) and page rendering.

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

Middleware runs in registration order. Non-short-circuiting requests fall through to Doors handler.

The request context in middleware carries `SessionContext` values (session-level, not instance-level). See [context.md](./03-context.md) for API compatibility. This is useful for auth bootstrapping — reading cookies and populating `SessionStore` before the handler runs.

## Options

```go
type With interface { /* passed to NewApp */ }

func WithConf(conf Conf) With                  // Runtime config
func WithCSP(csp CSP) With                     // Content Security Policy
func WithID(id string) With                    // Server ID for URLs & cookie naming
func WithLogger(l *slog.Logger) With           // Internal logger
func WithSessionTracker(t SessionTracker) With // Observe session create/delete
func WithErrorPage(ep ErrorPage) With          // Custom error page renderer
func WithESProfiles(f func(string) api.BuildOptions) With // esbuild profiles
```

`ESProfile{...}` also implements `With`.

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
