# GoX for Doors LLM agents

GoX compiles `.gox` templates to `.go`. Write HTML-like templates as typed Go expressions; the `gox` CLI generates `.x.go` next to each `.gox`.

## Contents

- [Prerequisites](#prerequisites)
- [Doors stack](#doors-stack)
- [Golden rule](#golden-rule)
- [Workflow](#workflow)
- [Syntax essentials](#syntax-essentials)
- [Rendering at runtime](#rendering-at-runtime)
- [Runtime extension interfaces](#runtime-extension-interfaces)
- [Doors helper APIs](#doors-helper-apis)
- [Common pitfalls](#common-pitfalls)

## Prerequisites

Run `gox ver` first — it must print a version (e.g. `v0.1.36`). Without `gox` on `PATH`, generation fails and builds error with `undefined: example` for every template.

Install:
- **Prebuilt binary (recommended):** download from [GitHub Releases](https://github.com/doors-dev/gox/releases), put on `PATH`.
- **From source:** `make install` — requires Go, Cargo, and a native toolchain (bundled Rust formatter). **No `go install ...@latest` shortcut** — native deps prevent it.

Stop and ask before installing if the environment forbids network access or global installs.

The Go module side is automatic: `go get github.com/doors-dev/gox` (or just `import` and `go mod tidy`). **Keep CLI and module versions in sync** — generated files carry a version marker and refuse mismatched runtimes. `gox ver` and the `// Managed by GoX vX.Y.Z` header must agree.

**Editor extension (always recommended).** Without it, `.gox` looks broken, go-to-definition/completion across `.gox`↔`.go` are disabled. Extensions also start the GoX language server (proxies `gopls`).
- VS Code: [`doors-dev/vscode-gox`](https://marketplace.visualstudio.com/items?itemName=doors-dev.gox)
- Neovim: [`doors-dev/nvim-gox`](https://github.com/doors-dev/nvim-gox)

Do not install or use `goxx` (`gox` extension package). Use Doors helper APIs for class composition, parallel render fragments, resources, actions, events, and attributes.

## Golden rule

**Always edit `.gox` files. Never edit/hand-write `.x.go` files. Never write templates in cursor style directly.** `.x.go` is overwritten on every `gox gen` (and by the language server on save). The cursor API is for runtime extension points (`Editor`, `Proxy`, `Printer`, custom `Modify`), not authoring.

Don't:
- Hand-write `gox.Elem(func(cur gox.Cursor) error { ... })` as authoring style — that's what `.gox` compiles *to*.
- Create new `.x.go` files (suffix is reserved; GoX may delete orphans).
- Read `.gox` first. Generated `.x.go` is useful only as a debugging/reference aid for lowered cursor calls, source-map positions, or low-level APIs.

## Workflow

```
gox fmt           # format .gox and .go (and embedded <script>/<style>)
gox gen           # regenerate .x.go for current directory
gox gen ./pkg     # regenerate a specific path
go run .          # build/run as normal Go
```

After editing `.gox`, run `gox gen` before `go build`/`go run`/`go test`. "undefined: MyElem" usually means missing regen.

**Always run `gox gen` after `gox fmt`.** Formatting shifts positions and invalidates the source map.

A typical package has all three side by side:
```
main.go      # regular Go
page.gox     # template source (edit this)
page.x.go    # generated (do not edit)
```

## Syntax essentials

A `.gox` file is a Go file plus the `elem` keyword and HTML literals. Use `.gox` only when the file needs template syntax (`elem`, HTML literals, fragments, placeholders, raw blocks, template control flow). Otherwise use `.go`. Top-level Go declarations (`import`, `type`, `func`, methods) are always normal Go and live outside `elem` bodies.

### HTML literals are Go expressions

Inside `.gox`, `<tag>...</tag>` is a `gox.Elem` value. Use anywhere a Go expression goes:

```gox
var greeting gox.Elem = <h1>Hi</h1>
type Card struct { Body gox.Elem }
card := Card{Body: <p>hello</p>}
func make() gox.Elem { return <b>x</b> }
```

`gox.Elem` implements `Main() gox.Elem`, satisfying `gox.Comp`.

### `elem` keyword

Shorthand for a function/method returning `gox.Elem`:

```gox
elem Greeting(name string) {
    <h1>Hello, ~(name)!</h1>
}
```

Equivalent generated API to:
```gox
func Greeting(name string) gox.Elem {
    return <h1>Hello, ~(name)!</h1>
}
```

**Render-time vs call-time:** an `elem` body evaluates when the element renders. A regular function returning `<...>` runs Go code before the `return` *immediately when called*. Idiom: use `elem` with a top `~{ ... }` setup block:

```gox
elem Page() {
    ~{ /* render-time setup */ }
    <main>...</main>
}
```

Visibility is standard Go: `elem Foo` exported, `elem foo` package-private.

Method form (typically `gox.Comp.Main`):
```gox
elem (u User) Main() { <li>~(u.Name)</li> }
```

Anonymous `elem() { ... }` exists. Prefer named helpers; use anonymous only when an inline template fn is the clearest fit.

**Pitfall:** `elem` is a reserved keyword. Cannot be used as variable/parameter/field name (e.g. `Proxy(cur, elem gox.Elem)` is a parse error — rename to `el`).

### Go statements: `~{ ... }`

Plain Go statements (`x := 1`, `if err != nil`, `sort.Slice(...)`, etc.) **cannot** appear bare in template syntax. Wrap them in `~{ ... }`:

```gox
elem UserList() {
    ~{
        type User struct { Name string }
        users := []User{{Name: "Ada"}, {Name: "Ben"}}
    }
    <ul>
        ~(for _, u := range users {
            <li>~(u.Name)</li>
        })
    </ul>
}
```

Inside `~{ ... }` you're in the generated render function (returns `error`).

**Top-of-`elem` setup block** (before any HTML emitted): validation, data loading, derived values, whole-component guards. From there, `return nil` skips the whole element; `return err` causes render error (do not use, prefer error branch rendering):

```gox
elem MaybePanel(show bool) {
    ~{ if !show { return nil } }
    <section>Visible</section>
}
```

**Don't `return nil` after output starts** — it exits before tags close, leaving broken HTML:

```gox
elem BrokenPanel() {
    <div>
        ~{ return nil }   // bad: exits before </div>
    </div>
}
```

Inside open markup, use `~(if ...)` or an inline `~func { return nil }` to skip only a child:

```gox
elem OptionalChild(show bool) {
    <div>
        ~// prefereable form:
        ~(if show { <span>Visible</span> })
        ~// in case of complex logic:
        ~func {
            if one {
                return nil
            }
            if second {
                return nil
            }
            /* ... */
            return <strong>Ready</strong>
        }
    </div>
}
```

**HTML tags create Go scopes.** Variables declared inside a tag body aren't visible to siblings. Declare shared values in a top-level `~{ ... }`:

```gox
elem SharedValue() {
    ~{ label := "GoX" }
    <h1>~(label)</h1>
    <p>~(label)</p>
}
```

### Placeholders: `~(expr)`

```gox
<p>~(user.Name)</p>
<p>~(a, " ", b, " ", c)</p>   // multi-arg, left-to-right
```

Parens **omittable only for literals** (string, numeric, composite):
```gox
<p>~"hello" ~42 ~User{Name: "Z"}</p>
```

**Pitfalls:**
- `~name` (bare identifier) is a parse error. Always `~(name)`.
-  whitespace: `~"a" ~"b"` renders `ab` and `~"a"~"b"` renders `ab`. For space to appear: `~("a", " ", "b")`.

### Text whitespace

Template indentation and blank lines are normilized, but spaces that are part of text content are preserved. A leading or trailing space next to real text is intentional and appears in output:

```gox
<span> Text</span>      // <span> Text</span>
<span>Text </span>      // <span>Text </span>
<span>Text ~(v)</span>  // text node is "Text ", then v
```

For multi-line text, indentation used to line up the template is removed. If the line has an extra space before or after the actual text, that extra space is preserved:

```gox
<span>
\t Text
</span>
// renders: <span> Text</span>

<span>
\tText
</span>
// renders: <span>Text</span>
```

Adjacent text-only lines are joined with a single space (`One` then `Two` renders `One Two`). Blank lines and whitespace-only lines render nothing. Text next to tags does not get an automatic separator: write an explicit leading/trailing space in the text when you need one.

`gox fmt` removes indentation and blank/edge whitespace that has no output effect; spaces that would be emitted are preserved.


### Control flow: `~(if ...)`, `~(for ...)`

Template control-flow placeholders: `if`/`else if`/`else` and `for`. Do not write `~(switch ...)`.

```gox
~(if loggedIn {
    Welcome, ~(name)!
} else if guest {
    Please log in.
} else {
    Bye.
})

~(for _, u := range users { <li>~(u.Name)</li> })
~(for i := 0; i < 3; i++ { <span>~(i)</span> })
```

Plain text can appear directly inside `~(if ...)` and `~(for ...)`. Use fragments only to group multiple sibling nodes:
```gox
~(if canCheckout {
    Secure checkout opens through Paddle.
} else {
    Checkout is not available right now.
})
```

If you need switch-like branching, prefer an `if`/`else if` chain in the template:
```gox
~(if state == "loading" {
    <p>Loading...</p>
} else if state == "done" {
    <p>Complete</p>
} else {
    <p>Unknown</p>
})
```

For a real `switch`, use an inline expression and return from each case:
```gox
~func {
    switch state {
    case "loading":
        return <p>Loading...</p>
    case "done":
        return <p>Complete</p>
    default:
        return nil
    }
}
```

### Inline func: `~func { ... }`

Render-time evaluation; the return value (text, component, or HTML literal) is inserted at that point (works in attibute values also). Use when logic exceeds a simple `~(if ...)`:

```gox
<div>
    ~func {
        user, err := db.Get(id)
        if err != nil { return <span>error</span> }
        switch user.Role {
        case "admin":
            return <strong>~(user.Name)</strong>
        }
        return Card(user)
    }
</div>
```

For conditions prefer `~(if ...)`. 

### Fragments: `<>...</>`

Group children without a wrapper tag:

```gox
elem Layout(body gox.Elem) { <body>~(body)</body> }

Layout(<>
    <h1>Title</h1>
    <p>Paragraph</p>
</>)
```

### Attributes

- String/numeric literal: `<div class="card" tabindex=0>`.
- Go expression in parens: `<div id=(id) title=(user.Bio)>`.
- Function literal (eval at render): `<input checked=func { return u.Agreed }>`.
- Bare attribute: `<input required>` ≡ `required=(true)`.
- `nil` or `false` → attribute omitted (cosmetic stray space may remain).
- `true` → bare name: `checked=(true)` → `checked`.
- **Names case-sensitive**: `class` ≠ `Class` (both emitted).
- **Output order: alphabetical**, not source order.

**No `~` in attribute values.** Use `id=(id)`, `class=(tone)`, `checked=func { return ok }` — never `id=~(id)` or `checked=~func { ... }`.

### Attribute Modifiers

Doors modifiers include event attrs, resources, `doors.Class`, and local `gox.Modify` values. Attach inside parens **inside the opening tag**:

```gox
<button (doors.Class("primary"))>Go</button>
<button (doors.Class("a"), doors.AClick{On: save})>Multi</button>   // comma-separated
<img (doors.ResourceFS(assets, "logo.svg"))>
```

**Writing your own `Modify`** is fine for reusable attribute bundles (design-system presets, analytics, form conventions):

```go
type Modify interface {
    Modify(ctx context.Context, tag string, attrs gox.Attrs) error
}

type PrimaryCTA struct { Label string }

func (p PrimaryCTA) Modify(_ context.Context, _ string, attrs gox.Attrs) error {
    attrs.Get("class").Set("btn btn-primary")
    attrs.Get("role").Set("button")
    attrs.Get("aria-label").Set(p.Label)
    return nil
}
// Usage: <button (PrimaryCTA{Label: "Save"})>Save</button>
```

Mutate via `attrs.Get(name).Set(value)` — **not** `attrs.Set(...)` (doesn't exist). For inline use: `gox.ModifyFunc(func(ctx, tag, attrs) error { ... })`.

### Void / self-closing elements

Standard HTML void tags (`<br>`, `<hr>`, `<img>`, `<input>`, `<meta>`, `<link>`, …) accept `<br>`, `<br/>`, `<br />` — all render `<br>`. **`</br>` is an error.**

### Reading helper docs: naming -> syntax

- **`AttrMod` / "modifier"** → modifier syntax: `<tag (x)>`.
- **`Proxy`** → proxy syntax: `~>(x) nextItem`.
- **Both** (e.g. `doors.Class`, `doors.A...` event attrs) → **default to modifier**. Use proxy only when you can't reach the target tag (wrapping a component whose outer tag you don't author):
  ```gox
  ~>(doors.Class("primary").Remove("disabled")) ~(BaseButton{})
  ```

Picking the wrong syntax usually produces a compile error or a no-op, not a silent bug.

### Per-attribute value hooks: `Mutate` and `Output`

Run on individual attribute *values* (not the whole attribute set):

```go
type Mutate interface {
    Mutate(name string, prev any) (newValue any)  // combine with previous value under same name
}
type Output interface {
    Output(w io.Writer) error  // value renders into attribute slot; GoX still escapes
}
```

`Mutate` builds class-style accumulators. `Output` controls serialization while keeping default escape.

### Text escaping

Text/placeholders are HTML-escaped:
```gox
<p>~("<script>")</p>   // → &lt;script&gt;
```

Escape the two characters GoX treats specially in template text by rendering string literals:
```gox
~"~"   // renders ~
~"}"   // renders an unmatched }
```

Raw block `<:>...</:>` emits literal HTML, whitespace preserved verbatim:
```gox
<svg viewBox="0 0 24 24">
    <:><path d="..." /></:>
</svg>
```

Useful for static SVG/HTML fragments. **Never pipe untrusted input through it.**

### Components (`gox.Comp`)

Anything with `Main() gox.Elem` is a component. In `.gox`, implement with `elem` method syntax:

```gox
type Card struct { Title string }

elem (c Card) Main() {
    <article>~(c.Title)</article>
}
```

Render via normal placeholder (no JSX-style `<MyComp/>`):
```gox
~(myComponent)        // identifier needs parens
~User{Name: "Z"}      // composite literal, parens optional
```

### `elem` helper vs component struct

Plain `elem Helper(args...)` for small stateless fragments with few params:
```gox
elem Badge(label string) { <span class="badge">~(label)</span> }
```

Use a component struct when:
- Many positional args would be needed
- Named fields read clearer (`Title`, `Body`, `Items`, callbacks, state)
- Multiple render helpers share data (receiver methods)
- Repeated composite-literal usage
- Constructor needs setup/defaults
- Must satisfy `gox.Comp`

**Keep HTML shape intact when extracting:** render parent wrappers in the parent, call helpers/components inside. Move a wrapper into a component only when the component owns it.

```gox
<section>
    ~Card{Title: "Build", Body: <p>Use GoX</p>}
    ~Card{Title: "Review", Body: <p>Check output</p>}
</section>
```

**Patterns:**

Data-shaped with child slot:
```gox
type Card struct {
    Title string
    Body gox.Elem
}
elem (c Card) Main() {
    <article>
        <h2>~(c.Title)</h2>
        ~(c.Body)
    </article>
}
```

Receiver helpers sharing fields:
```gox
type Menu struct {
    Active string
    Items []MenuItem
}
elem (m Menu) Main() {
    <ul>~(for _, item := range m.Items { ~(m.item(item)) })</ul>
}
elem (m Menu) item(item MenuItem) {
    <li class=func {
        if item.Slug == m.Active { return "active" }
        return nil
    }>
        <a href=(item.Path)>~(item.Title)</a>
    </li>
}
```

Constructor returning `gox.Comp` to hide setup:
```go
func NewSearch(users []User) gox.Comp {
    return searchBox{Users: users}
}
type searchBox struct { Users []User }
// elem (s searchBox) Main() { ... }
```

Page composition with named slots:
```gox
type PageShell struct { Header, Body, Footer gox.Elem }
elem (p PageShell) Main() {
    <div class="page">
        ~(p.Header)
        <main>~(p.Body)</main>
        ~(p.Footer)
    </div>
}
```

**Don't use `Main` as a field name** — collides with the render method (or tempts `~(p.Main)` rendering the method value). Use `Body`, `Content`, `Children`, `MainContent`.

For "wrap children in a tag" → `elem Layout(body gox.Comp)`. Named config/state/multiple methods → component.

### Children / slot pattern

Pass `Elem`/`Comp` as arg or struct field. Fragments build multi-node children:

```gox
elem Card(title string, body gox.Comp) {
    <article>
        <h2>~(title)</h2>
        ~(body)
    </article>
}

~(Card("Hi", <>
    <p>first</p>
    <p>second</p>
</>))
```

Same idea via struct field of type `gox.Elem` or `gox.Comp` (the latter accepts plain `gox.Elem` too).

### Comments

```gox
~// single-line template comment (not emitted)
~/* multi-line template comment */
<!-- emitted HTML comment -->
```


### Proxies: `~>(p) nextItem`

A `Proxy` captures the next renderable item at render time (element, component placeholder, `~func`, raw block, text, control-flow, or placeholder).

**Captures one item only.** `~>(p) Text ~(dd)` captures only `Text`. Group siblings into one item: wrapper element, fragment, or multi-value placeholder `~>(p) ~("Text ", dd)`.

Chain: `~>(p1) ~>(p2) item` ≡ `~>(p1, p2) item`. Outermost first; `p2` wraps the original, then `p1` wraps the result.

Doors proxies include `doors.Parallel`, `doors.Class` as proxy, `doors.ProxyMod`, `doors.A...` event attrs, and `doors.Door`. Import and attach them.

**Don't write a custom `Proxy` unless you truly need a low-level rendering transform.** Last resort. To wrap content -> component/slot. To set attributes -> `Modify`. To attach attributes through a wrapping component -> `doors.ProxyMod` or `doors.Class`. Custom proxies require careful cursor lifecycle.

Custom `Proxy` is for transforming captured output before emission — rewriting attrs on descendants, filtering printers, render metrics, retargeted output.

Common usage:
```gox
~>(doors.Parallel()) <section>~(LoadSlowStats(ctx))</section>
~>(doors.Class("primary")) ~(Button{})
~>(TestID("save")) ~(Button{})
~>doors.AClick{On: saveClick} ~(Button{})
~>(Track) ~func { return <span>computed</span> }
~>(Track) ~("Text ", dd)
~>(Track) Text
~>(p1, p2) <div>chained</div>
```

Type and sample (rarely needed):
```go
type Proxy interface {
    Proxy(cur gox.Cursor, e gox.Elem) error  // param name can't be `elem` in .gox
}

func (wrap) Proxy(cur gox.Cursor, e gox.Elem) error {
    if err := cur.Init("section"); err != nil { return err }
    if err := cur.Submit(); err != nil { return err }
    if err := e(cur); err != nil { return err }
    return cur.Close()
}
```

For one-offs: `gox.ProxyFunc(func(cur, e) error { ... })`.

### Raw HTML

`<:>...</:>` for static raw. For programmatic raw output, drop an `Editor` through a placeholder:
```gox
~(gox.EditorFunc(func(cur gox.Cursor) error {
    return cur.Raw("<mark>unescaped</mark>")
}))
```

Never pipe untrusted input through these.

## Runtime extension interfaces

Reach for these only when ordinary templating can't express the need. They live in `.go` files, not `.gox`.

- `gox.Editor` — `Edit(cur gox.Cursor) error`. Direct cursor for low-level emission. Use `gox.EditorFunc` for one-offs.
- `gox.Proxy` — `Proxy(cur gox.Cursor, e gox.Elem) error`. Intercepts next renderable. Prefer existing proxies.
- `gox.Modify` — `Modify(ctx, tag, attrs Attrs) error`. Head-level attribute transformer (`<tag (Modifier)>`). Use `gox.ModifyFunc`.
- `gox.Mutate` — `Mutate(name, prev any) any`. Value-level: combine with existing attribute under same name.
- `gox.Output` — `Output(w io.Writer) error`. Value controls own serialization (still escaped).
- `gox.Printer` — consumes the `Job` stream. Custom printers can buffer/transform/reroute.

**Cursor lifecycle when writing `Editor` / low-level code:**
1. Regular: `Init(tag)` → `AttrSet`/`AttrMod` → `Submit()` → children → `Close()`.
2. Void: `InitVoid(tag)` → `AttrSet` → `Submit()` (no `Close`).
3. Container: `InitContainer()` → children → `Close()` (no tag).

Before `Submit()` you may mutate attributes; after, the head is frozen but children may be emitted.

## Doors helper APIs

### Parallel rendering

Mark independent slow fragments with `~>(doors.Parallel())`. They render on the instance goroutine pool; output order stays deterministic.

```gox
elem Page() {
    <main>
        <h1>Dashboard</h1>
        ~>(doors.Parallel()) <section>~(SlowStats(ctx))</section>
        ~>(doors.Parallel()) <aside>~(SlowSidebar(ctx))</aside>
    </main>
}
```

Use for DB queries, outbound HTTP, FS reads, or heavy compute during render.

Do not put `doors.Parallel()` in front of `Source`/`Beam` `Bind`, `Effect`, `Route`, or `doors.Door` rendering. Dynamic/reactive regions already render on the Doors runtime.

### `doors.Class` — three-in-one class helper

Builds an immutable class set. Inputs split with `strings.Fields` (variadic and space-separated equivalent).

```go
doors.Class("button", "primary")
doors.Class("button primary")
doors.Class("button").Add("primary").Filter("hidden")
```

Three attachment styles:
```gox
// 1. Modifier (merges with class="..." on same element)
<button (doors.Class("button primary")) class="wide">Save</button>

// 2. Attribute value
<button class=(doors.Class("button", "primary"))>Save</button>

// 3. Proxy — propagates through containers/components to first real element
~>(doors.Class("button primary")) <button>Save</button>
```

Use `Add` to append classes, `Remove` to remove classes already in the current set, `Filter` to omit matching classes from final output, and `Join` to compose reusable groups:

```go
doors.Class("button").Filter("hidden").Add("hidden").String() // "button"
```

Useful for stripping a class baked into a component:
```gox
~>(doors.Class("primary").Filter("disabled")) ~(BaseButton{})
```

### `doors.ProxyMod` — attach `Modify` through wrappers

Carries a modifier through leading components/containers to the first real element, applies once, and leaves later siblings unchanged. `doors.Parallel()` markers are preserved.

```go
func TestID(id string) gox.Proxy {
    return doors.ProxyMod(gox.ModifyFunc(func(_ context.Context, _ string, attrs gox.Attrs) error {
        attrs.Get("data-testid").Set(id)
        return nil
    }))
}
```

```gox
elem Toolbar() {
    ~>(TestID("save-button")) ~(SaveButton{})
}
```

Captured item must begin with an element/component/container that resolves to an element. Text first is an error. `ProxyMod` cannot alter `doors.Door` content.

## Common pitfalls

1. **Edited `.x.go` by hand** — gone on next `gen`. Edit `.gox`.
2. **Wrote new templates in cursor style** (`gox.Elem(func(cur)...)`) in `.go` — write `.gox` instead.
3. **Plain Go statements bare in `elem` body** — wrap in `~{ ... }`.
4. **Render-time setup before `return <...>` in regular func** — runs at call time, not render. Use `elem` + top `~{ ... }`.
5. **Forgot `gox gen` after edit** — "undefined" build errors.
6. **Forgot `gox gen` after `gox fmt`** — source map drifts.
7. **Used `elem` as identifier name** — reserved keyword. Rename.
8. **`return nil` inside open markup** — breaks HTML. Guard at top of `elem`, or use `~(if ...)`/`~func { return nil }` for child-only skips.
9. **Variable from tag scope referenced later** — tags create scopes. Declare in top-level snippet.
10. **`~name` without parens** — parse error. Always `~(name)`. Parenless = literals only.
11. **Mixed `class` and `Class`** — separate attributes. Pick one casing - lower by default.
12. **Relied on attribute source order** — output is alphabetical.
13. **Tried `<MyComponent/>`** — no JSX. Use `~(myComponent)` or composite-literal placeholder.
14. **Used `Main` as field name** — collides with render method. Rename.
15. **Pure-Go file as `.gox`** — use `.go` when no GoX/HTML syntax.
16. **Expected different `elem` visibility** — same as Go (uppercase = exported).
17. **`~(...)` in attribute** — text/template positions only. Use `id=(id)`, `checked=func { ... }`.
18. **Called `attrs.Set(...)` in `Modify`** — method is `attrs.Get(name).Set(value)`.
19. **`</br>` / `</input>`** — void tags have no closing. Use `<br>`, `<br/>`, `<br />`.
20. **Unescaped via `~(untrustedHTML)`** — that escapes. `<:>...</:>` or `gox.EditorFunc + cur.Raw` for trusted only.
21. **Whitespace between placeholders** — `~(a) ~(b)`, `~(a)~(b)` have no space, `~(a, " ", b)` has.
22. **Expected raw template indentation/newlines** — normalized. Intentional spaces preserved. Use raw blocks for verbatim.
23. **Expected proxy to capture multiple siblings** — captures one. Group via fragment/wrapper/multi-value placeholder.
24. **Custom `Proxy` for ordinary wrapping/attributes** — use components, `Modify`, or `doors.ProxyMod` instead.
25. **Imported `gox` but unused in `.gox`** — fine; generated `.x.go` references `gox.Elem` for `elem` and HTML syntax, so module must be in `go.mod`.
26. **Version drift** — generated files have version markers; CI must use matching `gox`.
27. **Added `goxx` to a Doors project** — remove it and use Doors helpers.
