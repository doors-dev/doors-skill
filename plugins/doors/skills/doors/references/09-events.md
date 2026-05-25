# Events

DOM events connected to Go handlers through special attributes.

## Contents

- [Event Attr Types](#event-attr-types)
- [Request Types](#request-types)
- [Common Fields (all event attrs)](#common-fields-all-event-attrs)
- [Handler Return](#handler-return)
- [Flow](#flow)
- [Attach Styles](#attach-styles)
- [Reuse (activated attrs)](#reuse-activated-attrs)
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
| `AInput` | Input | `RequestEvent[InputEvent]` |
| `AChange` | Change | `RequestEvent[ChangeEvent]` |
| `ASubmit[T]` | Form submit (decoded) | `RequestForm[T]` |
| `ARawSubmit` | Form submit (raw) | `RequestRawForm` |

## Request Types

```go
type RequestEvent[E any] interface {
    RequestCommon   // SetCookie, GetCookie, Context()
    RequestAfter    // After(a Actions) error
    Event() E
}

type RequestCommon interface {
    SetCookie(cookie *http.Cookie)
    GetCookie(name string) (*http.Cookie, error)
    Context() context.Context   // HTTP request context, NOT Doors ctx
}
```

- `ctx` in handler = Doors runtime context (use for Doors APIs)
- `r.Context()` = HTTP request context — carries session-level values only (same as `SessionContext`), not instance-level. Use for HTTP-level operations; do not use for instance-scoped Doors APIs.

### PointerEvent

```go
type PointerEvent = front.PointerEvent  // Type, PointerID, Width, Height, Pressure, TangentialPressure, TiltX, TiltY, Twist, Buttons, Button, PointerType, IsPrimary, ClientX, ClientY, ScreenX, ScreenY, PageX, PageY, Timestamp
type RequestPointer = RequestEvent[PointerEvent]
```

### KeyboardEvent

```go
type KeyboardEvent = front.KeyboardEvent  // Type, Key, Code, Repeat, CtrlKey, ShiftKey, AltKey, MetaKey, Timestamp
type RequestKeyboard = RequestEvent[KeyboardEvent]
```

### FocusEvent

```go
type FocusEvent = front.FocusEvent  // Type, Timestamp
type RequestFocus = RequestEvent[FocusEvent]
```

### Input / Change

```go
type InputEvent = front.InputEvent    // Type, Name, Data, Value, Number, Date, Selected, Checked, Timestamp
type ChangeEvent = front.ChangeEvent  // Type, Name, Value, Number, Date, Selected, Checked, Timestamp
```

`AInput{ExcludeValue: true}` omits the current value fields from the payload. Use it when the input event data or the fact that editing happened is enough.

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

`ASubmit[T]` uses `github.com/go-playground/form/v4` for decoding form values into `D`. Follow that library's documentation for struct tag annotations. `MaxMemory` defaults to 8MB, passed to `ParseMultipartForm`.

For uploads or custom multipart parsing, use `ARawSubmit`, set an intentional parse limit with `ParseForm(maxMemory)` or `MaxMemory`, and treat filenames, content types, form fields, and file bytes as client-controlled. Validate by parsing/sniffing the content you accept; never trust the browser-provided filename or MIME type as proof, and do not accept/reject CSV solely by filename suffix.

## Common Fields (all event attrs)

```go
On       // handler (required)
Scope    // request scheduling (Scopes)
Indicator // temporary client-side feedback (Indicators)
Before   // client actions before request (Actions)
OnError  // client actions on failure (Actions)
```

Some also have:
- `PreventDefault bool` (pointer/key events)
- `StopPropagation bool` (pointer/key events and focus-in/focus-out)
- `ExactTarget bool` (pointer/key events and focus-in/focus-out)
- `Filter []string` (key events — match by `event.key`)
- `ExcludeValue bool` (input — omit value from payload)
- `MaxMemory int` (submit — multipart parse memory limit)

## Handler Return

- `false` — keep handler active (normal)
- `true` — handler done, remove it (one-shot)

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
~{
    radio := doors.A(ctx, doors.AChange{
        On: func(ctx context.Context, r doors.RequestEvent[doors.ChangeEvent]) bool { return false },
    })
}
<input type="radio" name="pick" value="a" (radio)/>
<input type="radio" name="pick" value="b" (radio)/>
```

Reusing one activated attr shares the same hook instance → serialized execution across elements.

## Unsupported Events

Wire custom events in JS with `$hook(...)` or `$fetch(...)` + `AHook[T]`/`ARawHook`. See [javascript.md](./15-javascript.md).

## Related

- [scopes.md](./11-scopes.md) — `Scope` field, scope types
- [indication.md](./12-indication.md) — `Indicator` field, indicator types
- [actions.md](./13-actions.md) — `Before`, `OnError`, `r.After(...)`
- [navigation.md](./10-navigation.md) — `ALink`
- [javascript.md](./15-javascript.md) — `AHook`, `$hook`
