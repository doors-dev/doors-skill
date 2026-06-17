# Shared Attribute

One Go handle controlling the same HTML attribute on all attached elements.

## Type

```go
type AShared = *aShared
```

## API

```go
func NewAShared(name string, value string) AShared  // starts enabled
func (a AShared) Update(ctx context.Context, value string)
func (a AShared) Enable(ctx context.Context)
func (a AShared) Disable(ctx context.Context)
```

`NewAShared` starts enabled, so attaching `doors.NewAShared("disabled", "")` renders `disabled` initially. In examples, make the intended initial state explicit; avoid `Enable`/`Disable` calls from render blocks just to correct initial state.

## Use Case

When one attribute is the whole job and several elements should stay in sync:
- `disabled`, `hidden`, `aria-*`, `data-*`
- Single-purpose `class` or `style`

NOT for rich DOM manipulation — use `ActionEmit` + `$on(...)` for that.

## Example

```gox
~~
locked := doors.NewAShared("disabled", "")
~~

<header>
    <button (locked)>Save draft</button>
</header>

<footer>
    <button (locked)>Publish</button>
</footer>

<button (doors.AClick{
    On: func(ctx context.Context, r doors.RequestPointer) bool {
        locked.Disable(ctx)
        return false
    },
})>Unlock actions</button>
```

One `Disable` call removes `disabled` from both buttons. `Enable` adds the shared attribute back.

## Rules

- One-attribute shared changes → `AShared`
- Richer DOM work → `ActionEmit` + `$on(...)`
- UI state change → normal rendering/state

## Related

- [actions.md](./13-actions.md) — `ActionEmit` as alternative
- [events.md](./09-events.md) — Event attrs
