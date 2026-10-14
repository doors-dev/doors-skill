# Title, Meta & Status

Page-level tools that behave differently from normal DOM content.

## Title & Meta

Render anywhere in the page tree — Doors moves them to `<head>`. Updates synced to browser on rerender.

```gox
elem Page() {
    <>
        <title>Docs</title>
        <meta name="description" content="Doors dev docs">
    </>
    <main><h1>Docs</h1></main>
}
```

### Meta identification

Uses `name` or `property` to identify which head tag to update:
```gox
<meta name="description" content="...">
<meta property="og:title" content="...">
```

### Mount/unmount semantics

Latest mounted render wins. When dynamic owner unmounts, Doors removes its title/meta and restores previous mounted value. App-level `<title>` can act as default, route-specific title overrides it while that route branch is mounted.

## Status

```go
func Status(statusCode int) gox.Elem
```

Sets HTTP status for **initial page response only**. Can render anywhere. Later reactive updates can't change the already-sent status code. A page HEAD request renders the page in full, so it answers with the same final status and headers as GET (no body).

```gox
elem NotFound() {
    <html><body>
        ~(doors.Status(404))
        <h1>Not found</h1>
    </body></html>
}
```

## Rules

- Render `<title>` and `<meta>` directly — Doors places them in `<head>`
- Use `name` or `property` on `<meta>` for identification
- Title/meta update on client when live page rerenders
- Title/meta updates apply as soon as they render, outside any batch: with `Batch` on a handler or `ALink`, or inside `OnBatch`, the title changes before the batched view lands. Render the title with the view it describes; do not count on it switching together.
- `Status` only affects initial response, not later instance updates

## Related

- [routing.md](./05-routing.md) — Route-specific titles
