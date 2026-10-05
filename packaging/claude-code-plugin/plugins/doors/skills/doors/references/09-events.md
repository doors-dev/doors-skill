# Events

DOM events connected to Go handlers through special attributes.

## Contents

- [Event Attr Types](#event-attr-types)
- [Request Types](#request-types)
- [Common Fields (all event attrs)](#common-fields-all-event-attrs)
- [Handler Return](#handler-return)
- [Errors](#errors)
- [Flow](#flow)
- [Attach Styles](#attach-styles)
- [Reuse (activated attrs)](#reuse-activated-attrs)
- [Race](#race)
- [Event Presets](#event-presets)
- [Unsupported Events](#unsupported-events)
- [Related](#related)

## Event Attr Types

| Attr | Event | Handler receives |
|------|-------|-----------------|
| `AClick` | Pointer click | `RequestPointer` |
| `APointerDown` | Pointer down | `RequestPointer` |
| `APointerUp` | Pointer up | `RequestPointer` |
| `APointerMove` | Pointer move | `RequestPointer` |
| `APointerOver` | Pointer over | `RequestPointer` |
| `APointerOut` | Pointer out | `RequestPointer` |
| `APointerEnter` | Pointer enter | `RequestPointer` |
| `APointerLeave` | Pointer leave | `RequestPointer` |
| `APointerCancel` | Pointer cancel | `RequestPointer` |
| `AGotPointerCapture` | Got pointer capture | `RequestPointer` |
| `ALostPointerCapture` | Lost pointer capture | `RequestPointer` |
| `AKeyDown` | Key down | `RequestKeyboard` |
| `AKeyUp` | Key up | `RequestKeyboard` |
| `AFocus` | Focus | `RequestFocus` |
| `ABlur` | Blur | `RequestFocus` |
| `AFocusIn` | Focus (bubbles) | `RequestFocus` |
| `AFocusOut` | Blur (bubbles) | `RequestFocus` |
| `AInput` | Input | `RequestInput` |
| `AChange` | Change | `RequestChange` |
| `ASubmit[T]` | Form submit (decoded) | `RequestForm[T]` |
| `ARawSubmit` | Form submit (raw) | `RequestRawForm` |

Server code can dispatch synthetic events (pointer, keyboard, focus, input, change, submit) to attached elements via `doors.Emitter`; emitted events bubble, so event attrs on ancestors run too. See [shared-attr.md](./17-element-handles.md).

## Request Types

```go
type RequestEvent[E any] interface {
    RequestCommon
    RequestAfter    // After(a Actions) error
    Event() E
}

type RequestCommon interface {
    SetCookie(cookie *http.Cookie)
    GetCookie(name string) (*http.Cookie, error)
    RequestHeader() http.Header
    RemoteAddr() string         // direct peer host:port; proxy headers not applied
    Context() context.Context   // HTTP request context, NOT Doors ctx
}
```

- `ctx` in handler = Doors runtime context (use for Doors APIs)
- `r.Context()` = HTTP request context — carries session-level values only (same as `SessionContext`), not instance-level. Use for HTTP-level operations; do not use for instance-scoped Doors APIs.

### PointerEvent

```go
type PointerEvent struct { ... }  // Type, PointerID, Pressure, TangentialPressure, TiltX, TiltY, Twist, Buttons, Button, PointerType, IsPrimary, Timestamp + geometry Rects: Pointer, Target, Page, Screen
type Rect struct { ... }          // X, Y, Width, Height (CSS px)
type RequestPointer = RequestEvent[PointerEvent]
```

Coordinates come from methods deriving from the rects: `OffsetX()/OffsetY()` (in target), `ClientX()/ClientY()` (viewport), `PageX()/PageY()` (document), `ScreenX()/ScreenY()` (screen).

### KeyboardEvent

```go
type KeyboardEvent struct { ... }  // Type, Key, Code, Repeat, CtrlKey, ShiftKey, AltKey, MetaKey, Timestamp
type RequestKeyboard = RequestEvent[KeyboardEvent]
```

`AKeyDown`/`AKeyUp` filter with `Keys Keys` — fires when the event matches any key. A `Key` is a `Keys` value on its own; combine with `.And(...)` or `doors.JoinKeys(...)`:

```go
Keys: doors.Key{Key: "Enter"}.And(doors.Key{Key: "s", CtrlMod: doors.ModOn})
```

```go
type Key struct {
    Key string  // event.key; "" matches any key
    CtrlMod, ShiftMod, AltMod, MetaMod Mod  // ModAny (default) | ModOn | ModOff
}
```

`doors.Key{Key: "s", CtrlMod: doors.ModOn}` matches Ctrl+S with any other modifiers; set the rest to `ModOff` for an exact combination. `PreventDefault`/`StopPropagation` apply only to matching events.

### FocusEvent

```go
type FocusEvent struct { ... }  // Type, Timestamp
type RequestFocus = RequestEvent[FocusEvent]
```

### Input / Change

```go
type InputEvent struct { ... }   // Type, Name, Data, Value, Number, Date, Selected, Checked, Timestamp
type ChangeEvent struct { ... }  // Type, Name, Value, Number, Date, Selected, Checked, Timestamp
type RequestInput = RequestEvent[InputEvent]
type RequestChange = RequestEvent[ChangeEvent]
```

`AInput{ExcludeValue: true}` fills only Type, Data, and Timestamp. Use it when the input event data or the fact that editing happened is enough.

### Forms

```go
type RequestForm[D any] interface {
    RequestCommon
    RequestAfter
    Data() D  // decoded from form using go-playground/form v4
}

type RequestRawForm interface {
    RequestCommon
    RequestAfter
    SetRequestBodyLimit(limit int)  // override body limit per request; negative disables
    ResponseWriter() http.ResponseWriter
    Reader() (*multipart.Reader, error)
    ParseForm(maxMemory int) (ParsedForm, error)
}

type ParsedForm interface {
    FormValues() url.Values
    FormValue(key string) string
    FormFile(key string) (multipart.File, *multipart.FileHeader, error)
    Form() *multipart.Form
}
```

`ASubmit[T]` uses `github.com/go-playground/form/v4` for decoding form values into `D`. Request body is bounded by `ServerRequestBodyLimit` (default 8 MB), which also serves as the max memory limit for form parsing.

For uploads or custom multipart parsing, use `ARawSubmit`, set an intentional parse limit with `ParseForm(maxMemory)`, and treat filenames, content types, form fields, and file bytes as client-controlled. Validate by parsing/sniffing the content you accept; never trust the browser-provided filename or MIME type as proof, and do not accept/reject CSV solely by filename suffix.

## Common Fields (all event attrs)

```go
On        // server handler (optional)
Scope     // request scheduling (Scopes)
Indicator // temporary client-side feedback (Indicators)
Before    // client actions before request (Actions)
OnError   // client actions on failure (Actions)
Race      // how overlapping calls are handled on the backend (default RaceSerial), see Race below
```

Nil `On`: the request is still sent and accepted (body discarded unread) and the hook stays registered — an attr can be attached purely for its client-side effects or as an `Emitter` round-trip target. Omit the attr entirely when nothing is needed.

Some also have:
- `PreventDefault bool` (pointer/key events)
- `StopPropagation bool` (pointer/key events and focus-in/focus-out)
- `ExactTarget bool` (pointer/key events and focus-in/focus-out)
- `Keys Keys` (key events — key + modifier matching, see [KeyboardEvent](#keyboardevent))
- `ExcludeValue bool` (input — omit value from payload)
- `RequestTimeout time.Duration` (`ASubmit`/`ARawSubmit`, also `AHook`/`ARawHook` — overrides `Conf.RequestTimeout` per hook; regular event attrs do not have it)


## Handler Return

- `false` — keep handler active (normal)
- `true` — handler done, remove it (one-shot)

A handler that hands work to a goroutine can keep the request pending past its return: `release := doors.HoldSettle(ctx)` keeps the indicator, the scope, and the `$hook` promise pending until `release()`. See [door.md](./07-door.md).

## Errors

- Attaching an event/form/hook attr on a released door fails the render with `context.Canceled`.
- Completion channels consumed inside handlers (`Call`, door operations) deliver sentinels for `errors.Is`: `ErrExecution` (action reached the browser and failed there), `ErrTerminated` (instance ended first).

## Flow

1. Browser event → build payload
2. Apply client options (PreventDefault, ExactTarget, etc.)
3. Run client-side scopes
4. Start indication
5. Run Before actions
6. Send request to server
7. Run Go handler
8. Run After actions (on success)
9. Run OnError actions (on failure)

## Attach Styles

### Attribute modifier (direct)

```gox
<button (doors.AClick{
    On: func(ctx context.Context, r doors.RequestPointer) bool { return false },
})>Click</button>
```

### Proxy (walks to first element)

```gox
~>doors.AClick{
    On: func(ctx context.Context, r doors.RequestPointer) bool { return false },
} <button>Click</button>
```

Proxy drills through components/containers to find the real element. Both forms are equivalent. Proxy form is more ergonomic with 3+ fields — it keeps the tag clean.

## Reuse (activated attrs)

```go
func A(ctx context.Context, a ...Attr) Attr
```

```gox
~~
radio := doors.A(ctx, doors.AChange{
    On: func(ctx context.Context, r doors.RequestEvent[doors.ChangeEvent]) bool { return false },
})
~~
<input type="radio" name="pick" value="a" (radio)/>
<input type="radio" name="pick" value="b" (radio)/>
```

Reusing one activated attr shares the same hook instance → one execution queue across elements (unless `Race: doors.RaceParallel`).

## Race

`Race` (all event attrs, `AHook`, `ARawHook`) sets how the backend handles overlapping calls to one hook:

| Value | Behavior |
|-------|----------|
| `doors.RaceSerial` (default) | one at a time, in order of arrival |
| `doors.RaceParallel` | calls run concurrently; handler must synchronize shared state; `true` result stops new calls, removal after running calls finish |
| `doors.RaceStrict` | one at a time; a call that arrives after a newer one is canceled instead of run (nothing is reordered; in-order calls all run) |

Use `RaceStrict` when only the newest input matters (live search, autosave, selection), so an older call never overwrites a newer result. A canceled call is silent on event attrs (`OnError` does not run); `$hook`/`$fetch`/`$sys.emit` reject with a canceled `HookErr`. `Race` is backend-side; scopes are client-side and combine with it (`ScopeLatest` + `RaceStrict`). `ALink` hooks are always strict; resource hooks (`NewHook`, script/style sources) are always parallel.

```gox
<input (doors.AInput{
    Race: doors.RaceStrict,
    On: func(ctx context.Context, r doors.RequestInput) bool { return false },
})/>
```

v0.16 removed the `Parallel bool` attr field and `Keys []Key`: `Parallel: true` → `Race: doors.RaceParallel`; `Keys: []doors.Key{a, b}` → `Keys: a.And(b)` or `doors.JoinKeys(a, b)`.

## Event Presets

When the same `Scope`, `Indicator`, and `OnError` appear on every handler, wrap the full attr in a small struct implementing `doors.Attr`. It holds only the varying fields and delegates `Proxy`/`Modify` to the underlying `doors.A...` type:

```go
var _ doors.Attr = SaveClick{}

type SaveClick struct {
	On func(context.Context, doors.RequestEvent[doors.PointerEvent]) bool
}

func (p SaveClick) Proxy(cur gox.Cursor, elem gox.Elem) error {
	return p.click().Proxy(cur, elem)
}

func (p SaveClick) Modify(ctx context.Context, tag string, attrs gox.Attrs) error {
	return p.click().Modify(ctx, tag, attrs)
}

func (p SaveClick) click() doors.AClick {
	return doors.AClick{
		Scope:     &doors.ScopeBlocking{},
		Indicator: doors.IndicateAttr("aria-busy", "true"),
		OnError: doors.ActionIndicate{
			Indicator: doors.IndicateClass("error"),
			Duration:  300 * time.Millisecond,
		},
		On: p.On,
	}
}
```

```gox
<button (SaveClick{
	On: func(ctx context.Context, r doors.RequestEvent[doors.PointerEvent]) bool {
		// save logic
		return false
	},
})>Save</button>
```

The same pattern works for any event attr family by wrapping the corresponding `doors.A...` type.

## Unsupported Events

Wire custom events in JS with `$hook(...)` or `$fetch(...)` + `AHook[T]`/`ARawHook`. See [javascript.md](./15-javascript.md).

## Related

- [scopes.md](./11-scopes.md) — `Scope` field, scope types
- [indication.md](./12-indication.md) — `Indicator` field, indicator types
- [actions.md](./13-actions.md) — `Before`, `OnError`, `r.After(...)`
- [navigation.md](./10-navigation.md) — `ALink`
- [javascript.md](./15-javascript.md) — `AHook`, `$hook`
- [shared-attr.md](./17-element-handles.md) — `Emitter` (synthetic events), `Setter`
- [door.md](./07-door.md) — `HoldSettle`, lifecycle hooks
