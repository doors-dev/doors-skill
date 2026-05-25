# Get Started

## Prerequisites

- Go >= 1.25.1
- GoX language server (VS Code / Neovim extension) + `gox` binary on PATH
- `.gox` files for templates, `.go` for plain Go, `.x.go` is generated (never edit)

## Starter Project

```bash
git clone --depth=1 https://github.com/doors-dev/doors-starter <project-name>
cd <project-name>
rm -rf .git
go mod edit -module <new-module-path>
# replace imports from github.com/doors-dev/doors-starter -> <new-module-path>
go mod tidy
gox fmt && gox gen
go test ./...
```

Structure:
```
path/          # path models (Go structs describing URL shapes)
components/    # reusable UI (nav, footer, 404)
segments/      # page groups, one per path model
  root/        #   main.gox (route dispatcher), landing, about, counter
assets/        # embedded static files
  embed.go     #   //go:embed directives for CSS bytes + fs.FS for UseFS
  static/      #   raw files served via UseFS middleware
main.go        # NewApp + app.Use(...) + ListenAndServe
app.gox        # HTML shell + head + doors.Route(...)
```


## Alternative: Minimal Project

```bash
mkdir myapp && cd myapp
go mod init example.com/myapp
go get github.com/doors-dev/doors
```

### app.gox

```gox
package main

import "github.com/doors-dev/gox"

type App struct{}

elem (a App) Main() {
    <!doctype html>
    <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>My App</title>
        </head>
        <body>
            <h1>Hello Doors!</h1>
        </body>
    </html>
}
```

### main.go

```go
package main

import (
    "context"
    "net/http"

    "github.com/doors-dev/doors"
    "github.com/doors-dev/gox"
)

func main() {
    app := doors.NewApp(func(ctx context.Context, r doors.Request) gox.Comp {
        return App{}
    })

    if err := http.ListenAndServe(":8080", app); err != nil {
        panic(err)
    }
}
```

Run with `go run .`.

## Key Principles

- `doors.NewApp(factory)` — factory receives `ctx` (Doors runtime context) and `doors.Request` (request/response headers and cookies). Returns the root component. Runs once per page request.
- `doors.App` implements `http.Handler` — plug into `http.ListenAndServe` or any Go mux.
- Routing happens *inside* the returned component via `doors.Route(...)`, not in the factory.
- Use `app.Use(...)` for HTTP middleware (static files, CORS, logging).
- Safari on `http://localhost` needs `doors.WithConf(doors.Conf{ServerSessionCookieNoSecure: true})`.

## Configuration (App)

```go
app := doors.NewApp(page,
    doors.WithConf(doors.Conf{RequestTimeout: 20 * time.Second}),
    doors.WithCSP(doors.CSP{ConnectSources: []string{"https://api.example.com"}}),
    doors.WithID("blue"),
)
```

## Related

- [app.md](./04-app.md) — App, middleware, page factory
- [routing.md](./05-routing.md) — Path models, route builders
- [configuration.md](./21-configuration.md) — All config options
