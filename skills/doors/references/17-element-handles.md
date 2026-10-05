# Element Handles

Go values attached to elements as attrs, acting on the live DOM from Go without a rerender. Two kinds:

- `Setter` — sets attributes on attached elements
- `Emitter` — dispatches synthetic DOM events to attached elements

Both are zero-value ready, attach as attr modifier or proxy (`(&h)`), and are stateless: they change live elements only. A re-rendered element returns to its template attributes — keep durable values in state/templates.

## Setter

```go
type Setter struct{}

func (s *Setter) Set(name string, value any) ActionInto[int]
```

`Set` returns an action for `Call` or any action-accepting API.
`Set(...).Into(&count)` captures the number of live elements reached, `0` when none is live.

Value semantics match template attributes:

- `nil`, `false` — remove the attribute
- `true` — set it bare
- `gox.Output` values serialize themselves
- anything else — formatted with `fmt`

`gox.Mutate` values (e.g. `doors.Class(...)`) fail the action — composing needs the previous attribute value, which only a rerender has. Pass a plain string instead: `Set("class", "hl")`.

Typical fits: `disabled`, `hidden`, `aria-*`, `data-*`, single-purpose `class`/`style`.

### Example

```gox
~~
var locked doors.Setter
~~

<header>
    <button (&locked)>Save draft</button>
</header>

<footer>
    <button (&locked)>Publish</button>
</footer>

<button (doors.AClick{
    On: func(ctx context.Context, r doors.RequestPointer) bool {
        doors.Call(ctx, locked.Set("disabled", true))
        return false
    },
})>Lock actions</button>
```

One call disables both buttons. `Set("disabled", nil)` removes the attribute again.

## Emitter

```go
type Emitter struct{}
```

Zero-value attribute handle. Each event method returns `ActionInto[int]` dispatching a real DOM event — bubbles, cancelable — so event attrs on the element **and its ancestors** run, and plain JS listeners see it too.

| Methods | Init struct |
| --- | --- |
| `Click`, `PointerDown`, `PointerUp`, `PointerMove`, `PointerOver`, `PointerOut`, `PointerEnter`, `PointerLeave`, `PointerCancel`, `GotPointerCapture`, `LostPointerCapture` | `PointerEmit` |
| `KeyDown`, `KeyUp` | `KeyboardEmit` |
| `Focus`, `Blur`, `FocusIn`, `FocusOut` | `FocusEmit` |
| `Input` | `InputEmit` |
| `Change` | `ChangeEmit` |
| `Submit` | `SubmitEmit` |

Init structs carry only round-trip fields; unset fields use browser defaults:

- `PointerEmit`: `PointerID`, `Buttons`, `Button`, `PointerType`, `IsPrimary`
- `KeyboardEmit`: `Key`, `Code`, `Repeat`, `CtrlKey`, `ShiftKey`, `AltKey`, `MetaKey` — an event matching no key of `AKeyDown`/`AKeyUp` `.Keys` sends no request
- `FocusEmit`: empty — runs handlers without moving focus
- `InputEmit`: `Data` — element values read from the event target
- `ChangeEmit`: empty — values read from the event target, attach the emitter to the input/select
- `SubmitEmit`: empty — form data read from the event target, attach the emitter to the form

`Into(&count)` captures the number of **hook requests** triggered, not elements reached: an attached element with no matching event attr adds nothing, a bubbling event adds one per event attr it reaches. Any failure among them fails the call. The action completes only after every triggered hook request has finished.

Event attrs accept nil `On` (request accepted, body discarded, hook stays) — an attr can exist purely as an Emitter round-trip target or for client-side effects.

### Example

```gox
~~
var field doors.Emitter
~~

<input type="text" (&field) (doors.AInput{
    On: func(ctx context.Context, r doors.RequestInput) bool {
        doors.Logger(ctx).Info("input", "data", r.Event().Data)
        return false
    },
})/>

<button (doors.AClick{
    On: func(ctx context.Context, r doors.RequestPointer) bool {
        doors.Call(ctx, field.Input(doors.InputEmit{Data: "hey"}))
        return false
    },
})>Simulate typing</button>
```

## Sharing

- One handle → many elements; many handles → one element (setter + emitter together is fine).
- Attaching the same handle to one element twice is harmless; it counts once.

## Rules

- Shared/targeted attribute changes → `Setter`
- Synthetic DOM events from server → `Emitter`
- Richer DOM work → `ActionEmit` + `$on(...)`
- UI state change → normal rendering/state
- `Into` units: `Setter` = live elements, `Emitter` = hook requests
- Same from JS → `$sys.emit(target, event)` (see `15-javascript.md`)

## Removed: AShared

v0.15 removed `AShared`/`NewAShared`; use `Setter`: `Enable`/`Update` → `Set(name, value)`, `Disable` → `Set(name, nil)`.

## Related

- [actions.md](./13-actions.md) — `Call`, `Into`, `ActionEmit`
- [events.md](./09-events.md) — event attrs an emitted event triggers
- [javascript.md](./15-javascript.md) — `ActionEmit` + `$on(...)`
- [state.md](./06-state.md) — changes that should survive a rerender
