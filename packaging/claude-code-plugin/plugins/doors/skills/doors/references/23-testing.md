# Testing Doors Apps

Use two layers:

- Pure Go business logic gets normal Go tests: services, queries, validation, authorization decisions, path-model helpers, encoders, parsers, and other functions that do not need a live Doors instance.
- Anything touching Doors state, rendering, hooks, navigation, sessions, resources, or browser behavior gets Rod-based e2e tests against a real `doors.App`.

Do not fake the Doors runtime for lifecycle or propagation behavior. If a test needs `Source`, `Beam`, `Lens`, `Bind`, `Effect`, hooks, `Door`, `ALink`, browser history, session cookies, resource injection, or DOM updates, drive it through a browser and assert the observable page result.

## What To Unit Test

Keep ordinary logic outside components and handlers when possible, then test it directly:

```go
func TestPriceLabel(t *testing.T) {
	got := PriceLabel(1299, "USD")
	if got != "$12.99" {
		t.Fatalf("expected label %q, got %q", "$12.99", got)
	}
}
```

Good unit-test targets:

- Database query builders and repository methods with explicit test databases
- Validation and permission functions
- Path model encode/decode edge cases
- Domain state transitions that do not require a Doors runtime context
- Formatting, sorting, filtering, and serialization

## What To Test With Rod

Use e2e tests when the behavior exists because the runtime, browser, or client script is involved:

- A hook mutates a `Source` and the DOM rerenders
- `Bind`, `Effect`, `Route`, route-derived `Source`/`Beam`, or `RouterBeam` selects the right subtree
- `ALink` updates the current instance, creates a new instance, or works with browser back/forward
- Form/input/key/pointer capture settings affect event payloads
- `Door.Inner`, `Door.Outer`, `Door.Static`, `Door.Reload`, or `X*` calls update the intended dynamic parent
- Session and instance storage survive or disappear at the right lifecycle boundary
- Head resources, scripts, styles, CSP, status, title, and meta are emitted correctly

Prefer user-visible assertions: text, attributes, classes, URL, HTTP status, cookies, and instance/session identity only when identity is the behavior under test.

## Decision Examples

| Behavior | Preferred test | Reason |
|----------|----------------|--------|
| Pure validation, formatting, sorting, or permission function | Go unit test | Deterministic logic, no runtime/browser contract |
| Path model escaping or query encode/decode | Go unit test | Pure adapter behavior; add e2e only for a full navigation flow |
| Repository/query function | Go unit or integration test | Test with a fake/test DB; use Rod only for the user flow that consumes it |
| `AClick` updates a `Source` and the page changes | Rod e2e | Exercises browser event, hook dispatch, state update, and rerender |
| `Bind`/`Effect` rerenders a dynamic subtree | Rod e2e | The contract is browser-visible runtime propagation |
| `Door.Inner`/`Outer`/`Reload` from a hook | Rod e2e | Depends on mounted lifecycle and DOM synchronization |
| `ALink` navigation and browser back | Rod e2e | Depends on link interception, URL sync, route state, and history |
| Session state shared across tabs/pages | Rod e2e | Browser cookies and multiple pages are part of the behavior |
| CSS/script/resource emitted into `<head>` | Rod e2e | Browser-visible document/resource behavior |

When a pure rule is only one part of a rendered interaction, test the rule directly and add a Rod e2e test for the user-facing interaction. For example, unit test validation logic, then e2e test that submitting invalid form data renders the error state.

## Minimal Rod Harness

Rod is a good fit for Doors because it is a Go browser driver with context-based timeouts, auto-waiting element helpers, `WaitStable`, `WaitRequestIdle`, and CI-friendly Chromium launching.

By default Rod uses its own Chromium and downloads it automatically when needed. Do not require developers or agents to install or locate a system browser unless the project explicitly needs a custom browser binary.

Start one browser per test package, then start a fresh app server per test. Use a random Doors server ID so cookies and runtime URLs do not collide between tests.

```go
package app_test

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/doors-dev/doors"
	"github.com/doors-dev/gox"
	"github.com/go-rod/rod"
	"github.com/go-rod/rod/lib/launcher"
	"github.com/go-rod/rod/lib/proto"
)

var browser *rod.Browser

func TestMain(m *testing.M) {
	l := launcher.New()
	if os.Getenv("CI") != "" || os.Getenv("GITHUB_ACTIONS") != "" {
		l = l.NoSandbox(true)
	}

	browser = rod.New().ControlURL(l.MustLaunch()).MustConnect()
	code := m.Run()
	browser.MustClose()
	os.Exit(code)
}

type testApp struct {
	base string
}

func newTestApp(t *testing.T, page func(context.Context, doors.Request) gox.Comp, opts ...doors.With) *testApp {
	t.Helper()

	baseOpts := []doors.With{doors.WithID(doors.IDRand())}
	app := doors.NewApp(page, append(baseOpts, opts...)...)

	l, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatal(err)
	}

	srv := &http.Server{Handler: app}
	done := make(chan error, 1)
	go func() {
		err := srv.Serve(l)
		if err != nil && err != http.ErrServerClosed {
			done <- err
			return
		}
		done <- nil
	}()

	t.Cleanup(func() {
		_ = srv.Close()
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	})

	return &testApp{base: "http://" + l.Addr().String()}
}

func (a *testApp) page(t *testing.T, path string) *rod.Page {
	t.Helper()

	url := a.base + path
	page := browser.MustPage("").Timeout(5 * time.Second)
	t.Cleanup(page.MustClose)

	var navErr string
	wait := page.EachEvent(
		func(e *proto.NetworkResponseReceived) bool {
			if e.Response.URL == url && e.Response.Status >= 400 {
				navErr = fmt.Sprintf("http %d: %s", int(e.Response.Status), e.Response.URL)
				return true
			}
			return false
		},
		func(e *proto.NetworkLoadingFailed) bool {
			navErr = fmt.Sprintf("request failed: %s", e.ErrorText)
			return true
		},
		func(_ *proto.PageLoadEventFired) bool {
			return true
		},
	)

	page.MustNavigate(url)
	wait()
	if navErr != "" {
		t.Fatal(navErr)
	}
	return page
}
```

This is a starting shape, not framework API. Keep the helper small and local to the app. Add only the knobs the app really needs: middleware, auth fixtures, test database, custom config, or header injection.

## Example E2E Shape

Render a real component, click real controls, and assert the browser-visible result:

```go
func TestCounterUpdates(t *testing.T) {
	app := newTestApp(t, func(ctx context.Context, r doors.Request) gox.Comp {
		return CounterPage{}
	})
	page := app.page(t, "/")

	page.MustElement("#count").MustWaitVisible()
	if got := page.MustElement("#count").MustText(); got != "0" {
		t.Fatalf("expected initial count 0, got %q", got)
	}

	page.MustElement("#increment").MustClick()
	page.MustElement("#count").MustWait(`() => this.textContent === "1"`)
}
```

For navigation, test both direct URL entry and link-driven navigation:

```go
func TestNavigationByLinkAndBack(t *testing.T) {
	app := newTestApp(t, pageFactory)
	page := app.page(t, "/docs/intro")

	page.MustElement("#article-title").MustWait(`() => this.textContent === "Intro"`)
	page.MustElement("#next-link").MustClick()
	page.MustElement("#article-title").MustWait(`() => this.textContent === "Install"`)

	page.MustNavigateBack()
	page.MustElement("#article-title").MustWait(`() => this.textContent === "Intro"`)
}
```

## Waiting Rules

Use Rod and DOM conditions instead of sleeps:

- Use `page.Timeout(...)` or `element.Timeout(...)` to bound waits.
- Use `MustWait`, `MustWaitVisible`, `MustWaitStable`, or `MustWaitRequestIdle` for asynchronous work.
- `MustWaitRequestIdle` is a two-step wait: create it before the action, trigger the action, then call the returned wait function.
- Assert after the UI condition that proves the hook/render cycle finished.
- Avoid fixed sleeps except for rare browser input quirks, and keep those sleeps inside one helper.

```go
wait := page.MustWaitRequestIdle()
page.MustElement("#refresh").MustClick()
wait()
```

Doors tests should usually wait for the final DOM state, not for an internal channel. That keeps tests aligned with what users actually experience.

## Avoid Bypass Tests

For runtime behavior, a good test has a visible precondition, a real browser action, and a visible postcondition.

- For hook tests, click/type/submit the real DOM element. Do not call the handler function directly.
- For user-action state tests, let the browser action mutate `Source`/`Lens`. Do not call `Update` directly unless direct state update is the behavior under test.
- For `ALink`, click the rendered link. Do not replace a link test with `page.MustNavigate(...)`; direct URL entry is a separate test.
- For `Door` updates, assert the mounted container and the changed child content. Do not only assert that some text appears somewhere.
- For routing/history, assert both DOM and URL/history when those are part of the behavior.
- Do not stop at “element exists” or “href is correct” when the feature is supposed to perform a runtime transition.

Bad tests often pass while testing nothing: they inspect initial HTML only, mutate state from the test process, call handlers directly, assert generated internals, or replace a browser transition with a direct navigation.

## Development And Agent Use

Rod is also useful outside committed tests. If an agent or editor harness does not provide a reliable browser controller, launch the app locally and use a short Rod script or temporary Go test to inspect the page, click through flows, read DOM text, or capture screenshots.

This is not a replacement for final tests. It is a practical investigation tool: when runtime behavior is visual or browser-mediated, looking through an actual browser beats guessing from server logs.

Convert an exploratory Rod check into a committed e2e test when it verifies user-facing behavior, prevents a regression, or documents framework integration behavior. Delete it when it was only a one-off debugging probe.

Do not reach for Rod for pure logic, formatting, validation, path encoding, query building, or authorization decisions that can be tested directly with ordinary Go tests.

## Practical Rules

- Keep e2e tests scenario-sized: one behavior per test, a few clicks, clear assertions.
- Use stable selectors such as `id` or `data-testid`; do not depend on incidental layout text for controls.
- Do not assert generated Doors attribute names, hook IDs, or resource hashes unless testing those internals directly.
- Close pages created by helpers when tests open many pages or run large suites, for example with `t.Cleanup(page.MustClose)`, unless intentionally keeping the page open for the test duration.
- Keep request timeouts realistic. Very low app request timeouts can create confusing client-system failures instead of testing the behavior you care about.
- In Linux CI, use `launcher.NoSandbox(true)` when Chromium sandboxing is unavailable.
- For manual Safari testing over plain `http://localhost`, configure `ServerSessionCookieNoSecure: true`; Chromium accepts secure cookies on localhost, Safari does not.

## Rod References

- Rod README and examples: `https://github.com/go-rod/rod`
- Rod API reference: `https://pkg.go.dev/github.com/go-rod/rod`
- Rod docs site: `https://go-rod.github.io/`
