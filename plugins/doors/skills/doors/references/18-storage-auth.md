# Storage & Auth

Key-value storage attached to session or instance lifetime. Primary use: auth state shared across pages/tabs.

## Store API

```go
type Store = ctex.Store

func SessionStore(ctx context.Context) Store   // shared across session
func InstanceStore(ctx context.Context) Store  // scoped to one page instance

func (s Store) Init(key any, fn func() any) any   // create once or return existing
func (s Store) Load(key any) any                   // get current value
func (s Store) Save(key any, value any) any        // replace, returns previous
func (s Store) Remove(key any) any                 // delete, returns previous
```

## Auth Pattern

### 1. Bootstrap in page factory

```go
type authKey struct{}

app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
    auth := doors.SessionStore(ctx).Init(authKey{}, func() any {
        c, err := r.GetCookie("session")
        if err != nil { return doors.NewSource(Session{}) }
        s, ok := driver.Sessions.Get(c.Value)
        if !ok { return doors.NewSource(Session{}) }
        return doors.NewSource(Session{Authorized: true, User: s.User})
    }).(doors.Source[Session])
    return App{auth: auth}
})
```

`Init` returns existing value if already created in the same session. Later requests receive the same shared `Source`.

### 2. Render from App fields

```gox
type App struct {
    auth doors.Source[Session]
}

elem (a App) Main() {
    ~(a.auth.Bind(elem(s Session) {
        ~(if !s.Authorized { <p>Log in</p> } else { <p>~(s.User.Name)</p> })
    }))
}
```

### 3. Login handler

```go
func login(ctx context.Context, r doors.RequestForm[LoginData]) bool {
    auth := doors.SessionStore(ctx).Load(authKey{}).(doors.Source[Session])

    session := driver.Sessions.Add(r.Data().Login, sessionDuration)
    r.SetCookie(&http.Cookie{
        Name: "session", Value: session.Token,
        Path: "/", HttpOnly: true,
    })
    doors.SessionExpire(ctx, sessionDuration) // cap Doors session to auth lifetime
    auth.Update(ctx, Session{Authorized: true, User: session.User})
    return true
}
```

### 4. Logout handler

```go
func logout(ctx context.Context, r doors.RequestPointer) bool {
    auth := doors.SessionStore(ctx).Load(authKey{}).(doors.Source[Session])

    if c, err := r.GetCookie("session"); err == nil {
        driver.Sessions.Remove(c.Value)
    }
    r.SetCookie(&http.Cookie{Name: "session", Path: "/", MaxAge: -1, HttpOnly: true})
    doors.SessionExpire(ctx, 0) // remove auth-duration cap; session reverts to default lifetime
    auth.Update(ctx, Session{})
    return true
}
```

Shared reactive session state means open pages react to auth changes immediately.

### Protected routes

Route matching is not authorization. Use Route primitives for route dispatch, then bind auth only inside branches that need it:

```gox
elem ProtectedPage(path doors.Source[Path], auth doors.Source[Session]) {
    ~(path.Route(
        doors.RouteMatch(func(p Path) bool { return p.Route == RouteDashboard }).Source(elem(dash doors.Source[Path]) {
            ~(auth.Bind(elem(s Session) {
                ~(if !s.Authorized {
                    ~(NewLoginPage(auth))
                } else {
                    ~(Dashboard{user: s.User, auth: auth, path: dash})
                })
            }))
        }),
        doors.RouteMatch(func(p Path) bool { return p.Route == RouteLogin }).Comp(NewLoginPage(auth)),
        doors.RouteDefaultComp[Path](HomePage{}),
    ))
}
```

If the whole app shell requires authorization, it is also fine to bind auth first and route inside the authorized branch:

```gox
~(auth.Bind(elem(s Session) {
    ~(if !s.Authorized {
        ~(NewLoginPage(auth))
    } else {
        ~(path.Route(
            doors.RouteMatch(func(p Path) bool { return p.Route == RouteDashboard }).Comp(Dashboard{}),
            doors.RouteDefaultComp[Path](HomePage{}),
        ))
    })
}))
```

For larger branch-local auth logic, keep route dispatch in `.Route(...)` and compute only the auth-dependent body inside the matched branch:

```gox
doors.RouteMatch(func(p Path) bool { return p.Route == RouteDashboard }).Source(elem(dash doors.Source[Path]) {
    ~(auth.Bind(elem(s Session) {
        ~func {
            if !s.Authorized {
                return NewLoginPage(auth).Main()
            }
            return Dashboard{user: s.User, auth: auth, path: dash}.Main()
        }
    }))
})
```

Avoid this shape:

```gox
~(auth.Bind(elem(s Session) {
    ~{
        p := path.Get() // not subscribed to path changes
    }
    ...
}))
```

Route-only changes can be missed because `Get` does not subscribe.

Update route state after successful login/logout handlers when you want an in-app navigation:

```go
auth.Update(ctx, Session{Authorized: true, User: user})
path.Update(ctx, Path{Route: RouteDashboard})
```

Do not call `path.Update`, `auth.Update`, or other state mutations from inside a render path (`Bind` callback, `Effect` body, or `~{...}` block) just to redirect an unauthenticated user. Render the allowed view from the current auth state, or perform navigation from the handler/app bootstrap path that caused the state change.

If a login component needs local error/message state, initialize that `Source` in an ordinary Go constructor or accept it from a parent before using it in `Bind` or the submit handler:

```go
type LoginPage struct {
    auth    doors.Source[Session]
    message doors.Source[string]
}

func NewLoginPage(auth doors.Source[Session]) LoginPage {
    return LoginPage{
        auth:    auth,
        message: doors.NewSource(""),
    }
}
```

Do not pass a path source to `LoginPage` unless it reads or writes the route; use a callback or route source intentionally when login must navigate. Do not render `LoginPage{auth: auth}` if its `Main()` calls `p.message.Bind` or `p.message.Update`; that leaves `message` nil.

## Advanced Auth (OAuth Flows)

When you need external OAuth flows, the simple page-factory bootstrap is not enough. The advanced pattern uses three layers:

### 1. Middleware: per-request token lifecycle

The request context in middleware (`app.Use(...)`) carries session-level values, so `SessionStore` is accessible. Middleware runs on every HTTP request — this is the right place to renew tokens and update cookies. Doors frontend sends sync requests roughly every 15 seconds, so token renewal operates naturally through this flow.

Middleware responsibilities:
- Init the auth service via `SessionStore.Init` (lazily created once per session)
- Read auth cookies from the incoming request
- Validate tokens (parse JWT or compare to cached session)
- Refresh tokens against the external provider when close to expiration
- Exchange a refresh token for a new token pair when the access token is missing
- Set updated cookies on the response when tokens are rotated
- Deauth the shared session state when no valid tokens are present

### 2. Auth service: goroutine with session lifetime

The service stores a `Source[Session]` and exposes `Session() Beam[Session]` so components can subscribe. It also exposes a `Deauth` method for logout. A goroutine runs with session context lifetime and exits when the session ends.

The goroutine should:
- Serialize all state mutations (no concurrent access to service fields)
- Periodically check session validity with the external provider
- Expire local shared state when the access token has not been refreshed for too long
- Update the shared `Source[Session]` so components react to auth changes

### 3. App factory: external auth callbacks

The app factory receives `doors.Request` and has access to the router. Use it to handle OAuth/PKCE callbacks: read the `code` query param, exchange it for tokens, update session state, and clean the URL.

```go
app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
    router := doors.Router(ctx)
    location := router.Get()
    if code := location.Query.Get("code"); code != "" {
        clean := location.Clone()
        clean.Query.Del("code")
        router.Update(ctx, clean)
        auth.ExchangeCode(r, code)
    }
    return App{}
}
```

## Instance Storage

Use for page-local state that survives rerenders but shouldn't sync across tabs.

## Rules

| When | Where |
|------|-------|
| UI should react to change | Store a `Source` in the store |
| Auth state | Session storage, NOT instance |
| Bootstrap | Page factory via `Init` |
| Cookie validation | Against real backend session store, not cookie alone |
| Session lifetime | Cap with `SessionExpire` on login |
| Logout/deauth | Clear cookie, remove backend session, `SessionExpire(ctx, 0)`, update shared source |
| Force-close session | `SessionEnd(ctx)` only for intentional full teardown |
| Cookie refresh/validate on every request | Middleware (`app.Use(...)`) — request context has session-level access |
| External auth callback (OAuth/PKCE) | App factory — read query, exchange, update state, clean URL |

## Related

- [session-instance.md](./19-session-instance.md) — `SessionExpire`, `SessionEnd`, `SessionContext`
- [state.md](./06-state.md) — `Source`, `Beam`, `DeriveSource`
- [context.md](./03-context.md) — When to use which context
- [background-data.md](./22-background-data.md) — Session-scoped background goroutines using `SessionStore.Init`
