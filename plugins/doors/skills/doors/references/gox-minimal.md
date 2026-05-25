# GoX Minimal Fallback

Use this only when the official GoX LLM reference is unavailable:

- `https://raw.githubusercontent.com/doors-dev/gox/refs/heads/main/llms.md`

This file is intentionally incomplete. It is a local safety net for common Doors work, not a replacement for the GoX reference.

## Contents

- [Workflow](#workflow)
- [Files](#files)
- [Elements](#elements)
- [Components](#components)
- [Placeholders](#placeholders)
- [Control Flow](#control-flow)
- [Attributes](#attributes)
- [Go Blocks](#go-blocks)
- [Proxies](#proxies)
- [Raw HTML](#raw-html)
- [Doors Rules](#doors-rules)

## Workflow

- Put templates and `elem` declarations in `.gox` files.
- Put ordinary Go-only code in `.go` files when no template syntax is needed.
- Treat `.x.go` files as generated output. Do not edit them by hand.
- Run `gox fmt` after changing `.gox`.
- Run `gox gen` when generated files are stale, missing, or causing compile errors.
- Run `go test ./...` after generation when the project has tests.

## Files

A `.gox` file is still Go source with a package, imports, types, and functions:

```gox
package main

import "github.com/doors-dev/gox"

type App struct{}

elem (a App) Main() {
    <main>Hello</main>
}
```

## Elements

HTML compiles to `gox.Elem` and can appear where a Go expression is expected:

```gox
var title gox.Elem = <h1>Hello</h1>

func Header() gox.Elem {
    return <header>Welcome</header>
}
```

Use fragments when multiple siblings are needed without adding a wrapper:

```gox
<>
    <h1>Title</h1>
    <p>Body</p>
</>
```

## Components

`elem` declares a function or method returning `gox.Elem`:

```gox
elem Button(label string) {
    <button>~(label)</button>
}

type Card struct {
    Title string
}

elem (c Card) Main() {
    <section>
        <h2>~(c.Title)</h2>
    </section>
}
```

A component is anything with `Main() gox.Elem`. Doors root components usually implement `Main()`.

## Placeholders

Use `~(...)` to render Go expressions inside markup:

```gox
elem UserRow(name string, count int) {
    <p>~(name, " has ", count, " items")</p>
}
```

The placeholder can render strings, numbers, `gox.Elem`, `gox.Comp`, slices of renderable values, and other values handled by GoX formatting.

Do not use JSX-style `{expr}` interpolation in GoX templates. Literal braces are markup/text; render Go values with `~(expr)`.

## Control Flow

Use Go control flow inside placeholders. This fallback only documents `if` and `for` as known-safe template control flow; do not invent other placeholder forms from memory when the official GoX reference is unavailable.

```gox
elem UserList(users []User) {
    <ul>
        ~(for _, user := range users {
            <li>~(user.Name)</li>
        })
    </ul>
}
```

If you need switch-like branching, prefer an `if`/`else if` chain in the template:

```gox
elem StatusLabel(state string) {
    ~(if state == "loading" {
        <p>Loading...</p>
    } else if state == "done" {
        <p>Complete</p>
    } else {
        <p>Unknown</p>
    })
}
```

For a real `switch`, use an inline expression and return from each case:

```gox
elem StatusLabel(state string) {
    ~func {
        switch state {
        case "loading":
            return <p>Loading...</p>
        case "done":
            return <p>Complete</p>
        default:
            return <p>Unknown</p>
        }
    }
}
```

```gox
elem Greeting(user *User) {
    <div>
        ~(if user != nil {
            <span>Hello ~(user.Name)</span>
        } else {
            <span>Please sign in</span>
        })
    </div>
}
```

## Attributes

Use normal HTML attributes for literals and `(expr)` for Go values:

```gox
elem Link(url string, active bool) {
    <a href=(url) aria-current=(active)>Open</a>
}
```

`false` and `nil` attribute values are omitted.

Attach attribute modifiers inside an opening tag:

```gox
<button (doors.AClick{On: handleClick})>Save</button>
```

## Go Blocks

Use `~{ ... }` for ordinary Go statements during rendering:

```gox
elem Profile(id string) {
    ~{
        user := loadUser(id)
    }
    <h1>~(user.Name)</h1>
}
```

In Doors `elem` blocks and `~{ ... }` blocks, `ctx context.Context` is implicitly available as the Doors runtime context.

## Proxies

Use `~>` to apply a proxy to the next element or component:

```gox
~>doors.AClick{On: handleClick} <button>Save</button>
```

For Doors event attrs, modifier and proxy forms are both common:

```gox
<button (doors.AClick{On: handleClick})>Save</button>
~>doors.AClick{On: handleClick} <button>Save</button>
```

## Raw HTML

Use `<:>...</:>` for raw static HTML that should not be escaped or interpreted as GoX:

```gox
<svg viewBox="0 0 24 24">
    <:><path d="M0 0h24v24H0z" /></:>
</svg>
```

## Doors Rules

- If the project depends on `github.com/doors-dev/doors`, do not add `goxx`.
- Use Doors helpers such as `doors.Class`, `doors.ProxyMod`, event attrs, and `Door` proxies according to the Doors references.
- Prefer changing `.gox`, then regenerating with `gox gen`, over editing generated `.x.go`.
