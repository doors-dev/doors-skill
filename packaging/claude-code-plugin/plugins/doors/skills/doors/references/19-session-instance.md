# Session & Instance

Lifecycle control for sessions and instances.

## API

```go
func SessionExpire(ctx context.Context, d time.Duration)   // cap session lifetime (d=0 removes cap)
func SessionEnd(ctx context.Context)                       // force-end whole session + all instances
func InstanceEnd(ctx context.Context)                      // end only this page instance
func SessionID(ctx context.Context) string                 // session ID (= session cookie value)
func InstanceID(ctx context.Context) string                // instance ID (for logging/tracing)
func HasSession(ctx context.Context) bool                  // ctx carries a Doors session; never panics
func HasInstance(ctx context.Context) bool                 // ctx belongs to a render/handler; implies HasSession
func SessionLastSeen(ctx context.Context) time.Time        // last session renewal (renewals are throttled)
func InstanceLastSeen(ctx context.Context) time.Time       // last client contact on live connection; zero during initial render
func IDNumber(ctx context.Context) uint64                  // instance-unique non-sequential number; needs instance ctx
func Logger(ctx context.Context) *slog.Logger              // Doors logger; slog.Default without session; any ctx
func SessionContext(ctx context.Context) context.Context   // context canceled on session end
func InstanceContext(ctx context.Context) context.Context  // context for instance-scoped goroutines
func DetachedContext(ctx context.Context) context.Context  // detached context: own goroutines, delivers completion results
```

## Lifecycle

- Request without a Doors session cookie gets a cookie on the response right away, but the session itself is created **lazily, on first actual touch** — requests that never use it (static resources, requests fully handled by `app.Use` middleware or `doors.UseResource`, crawlers) allocate no session state
- Rendering a page touches the session; a session-scoped API call on a middleware/request ctx also creates it on first use
- Session renewed on later requests, timer-based TTL starting at creation
- Each page open gets its own instance
- `WithSessionTracker` (app option) observes session lifecycle; repeating the option installs several observers, run in registration order

### Config fields (Conf)

| Field | Default | Purpose |
|-------|---------|---------|
| `SessionInstanceLimit` | 12 | Max instances per session (older suspended when exceeded) |
| `SessionTTL` | (auto) | Session lifetime after last request; values at or below `InstanceTTL` raised to it |
| `InstanceConnectTimeout` | `RequestTimeout` | New instance must connect within this |
| `InstanceTTL` | 40m | Inactive instance kept alive; never below `2 * RequestTimeout` |
| `InstanceGoroutineLimit` | 8 | Max runtime goroutines per instance |
| `DisconnectHiddenTimer` | `InstanceTTL/2` | Hidden pages stay connected for this long before disconnecting |
| `RequestTimeout` | 30s | Max client request/hook call duration |

## Cookie

Internal Doors session cookie: `HttpOnly`, `Secure`, scoped to `/`, named from `ServerSessionCookiePrefix + WithID` (default: `doors`).

- `ServerSessionCookieNoSecure`: omit `Secure` for plain HTTP dev
- `ServerSessionCookiePrefix`: e.g. `__Host-` or `__Secure-` for browser prefix rules

## When to Use

| API | When |
|-----|------|
| `SessionExpire` | Login — cap Doors session to your auth session lifetime |
| `SessionExpire(ctx, 0)` | Logout — remove explicit cap, back to normal TTL |
| `SessionEnd` | Hard logout, security event, force account switch |
| `InstanceEnd` | Detached page finished, discard this tab only |
| `HasSession` / `HasInstance` | Check which Doors API level a context supports before calling |
| `SessionContext` | Session-scoped goroutines, shared helpers, Door handle methods, Source/Beam mutations, reads, and subscriptions (subs end with the session) |
| `InstanceContext` | Work outliving current dynamic owner, bounded by page |
| `DetachedContext` | Own goroutines keeping current ownership; waiting on completion channels |

## Session vs Instance Store

| Store | Shared across | Use for |
|-------|--------------|---------|
| `SessionStore` | All pages/tabs in session | Auth, theme, locale |
| `InstanceStore` | One page instance | Page-local state |

## Rules

- `SessionExpire` is a *cap*, not a keepalive — earlier TTL wins
- Prefer updating shared reactive state over `SessionEnd` for logout
- `SessionEnd` affects all tabs immediately
- `InstanceEnd` leaves other tabs untouched
- Use `SessionID`/`InstanceID` for diagnostics only, not business identifiers
- `SessionContext` drops user ctx values; `InstanceContext`/`DetachedContext` keep them
- Top-level `doors.Reload`, `doors.DeferredInner`/`DeferredOuter`/`DeferredStatic` and instance APIs panic on `SessionContext`; Door handle methods accept it

## Related

- [storage-auth.md](./18-storage-auth.md) — Store API, auth pattern
- [context.md](./03-context.md) — Context types and their API compatibility
- [configuration.md](./21-configuration.md) — `Conf` fields
