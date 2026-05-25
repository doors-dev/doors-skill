# Session & Instance

Lifecycle control for sessions and instances.

## API

```go
func SessionExpire(ctx context.Context, d time.Duration)   // cap session lifetime (d=0 removes cap)
func SessionEnd(ctx context.Context)                       // force-end whole session + all instances
func InstanceEnd(ctx context.Context)                      // end only this page instance
func SessionId(ctx context.Context) string                 // session ID (for logging/tracing)
func InstanceId(ctx context.Context) string                // instance ID (for logging/tracing)
func SessionContext(ctx context.Context) context.Context   // context canceled on session end
func InstanceContext(ctx context.Context) context.Context  // context for instance-scoped goroutines
func DetachedContext(ctx context.Context) context.Context  // context detached from render frame
```

## Lifecycle

- Session created on first request without existing Doors session cookie
- Session renewed on later requests, timer-based TTL
- Each page open gets its own instance

### Config fields (Conf)

| Field | Default | Purpose |
|-------|---------|---------|
| `SessionInstanceLimit` | 12 | Max instances per session (older suspended when exceeded) |
| `SessionTTL` | (auto) | Session lifetime after activity; if unset or too small, raised to at least `InstanceTTL` |
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
| `SessionContext` | Session-scoped goroutines, shared helpers, Door handle methods, and Source/Beam mutations; use instance/render context for Source/Beam reads |
| `InstanceContext` | Work outliving current dynamic owner, bounded by page |
| `DetachedContext` | Work keeping current dynamic ownership |

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
- Use `SessionId`/`InstanceId` for diagnostics only, not business identifiers

## Related

- [storage-auth.md](./18-storage-auth.md) — Store API, auth pattern
- [context.md](./03-context.md) — Context types and their API compatibility
- [configuration.md](./21-configuration.md) — `Conf` fields
