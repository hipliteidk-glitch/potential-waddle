# Tests

```bash
node test-parser.js            # upstream command parser
node test-target.js            # target profiles (no Roblox regression)
node test-deepseek-model.js    # DeepSeek model choice + vision gating
node test-arena-mode.js        # Arena chat-mode gate
node test-arena-agent.js       # Arena Agent Mode logic

npm install --no-save jsdom
node test-arena-agent-dom.js   # the REAL provider against a REAL DOM
```

## Why `test-arena-agent-dom.js` exists

The other suites re-implement a provider's logic inline and assert on the copy.
That catches design mistakes, but **not** the failure that actually happened
live: the shipped file querying a selector that matches nothing. A test that
re-implements the code can pass while the code is broken.

`test-arena-agent-dom.js` loads `providers/arena-agent.js` **verbatim** into a
jsdom document built from markup captured on arena.ai/agent — including the
ancestor chain of the JSON widget whose reply went undetected — then calls the
real `allItems()` / `lastAssistant()` / `readAssistant()` and feeds the result
to the real `core/parser.js`.

It is skipped with a notice if jsdom is absent, so the other suites still run.

## Mutation-checked

The test is only worth anything if it fails when the code breaks. Verified by
reintroducing each real bug and confirming it is caught:

| Reintroduced bug | Result |
| --- | --- |
| turns keyed on the outer wrapper (`div.px-3`) | 6 failures |
| composer guard removed | 7 failures |
| widget check removed (`text only`) | 4 failures |

The third initially **survived**, because the fixture's widget contained text,
so `txt.length > 0` short-circuited the widget check. A reply whose widget has
no text of its own was added to the fixture; it now fails as it should.

## Live browser test (Playwright)

`e2e/arena-agent.spec.js` drives a real Chromium with the extension loaded.
It cannot run in this sandbox (arena.ai is unreachable, HTTP 000), so it is
for **your** machine:

```bash
npm install --no-save @playwright/test && npx playwright install chromium
npx playwright open --save-storage=e2e/.auth.json https://arena.ai   # sign in once
npx playwright test e2e/arena-agent.spec.js
```

Four things the obvious version of this test gets wrong, and how this one
handles them:

| Pitfall | Handling |
| --- | --- |
| Playwright's default `page` has **no extension** loaded, so any overlay assertion fails by construction | uses `launchPersistentContext` with `--load-extension` (MV3 needs a persistent profile) |
| `#zeroscript-overlay` / `.zs-overlay` / `[data-zs-extension]` **do not exist** in the source | asserts the real ids: `#zs-root`, `#zs-bar` |
| arena.ai requires a **login**; anonymous runs hit a sign-in wall and fail for unrelated reasons | detects the signed-out state and **skips** with instructions |
| Text assertions on third-party marketing copy are brittle | prefers `aria-label` / role handles; text checks kept advisory |

The third test reproduces the actual live regression: it asks the model for a
JSON code block and asserts the provider's turn query sees it — the failure
that produced "Arena Agent did not respond in time".

## Self-test: making the extension testable from anywhere

The providers are DOM reverse-engineering against sites a developer often
cannot reach. Every provider bug this session followed the same slow loop: hit
a failure, paste a screenshot, guess a fix, repeat. Unit tests that
re-implement a provider's logic cannot catch a selector that matches nothing on
the real page.

The extension can now report that itself.

**Capture (on the machine with the site open)**

1. Open the AI chat where it misbehaves.
2. Click the ZeroScript icon → **🧪 Run self-test & copy report**.
3. A readable PASS/FAIL report appears; the full report *plus a replayable DOM
   fixture* is copied to the clipboard.

The report answers the questions that actually matter: is the provider loaded,
is the composer found, how many turns does `allItems()` see, is the composer
being misread as a reply, does the newest reply parse into a command.

**Replay (offline, forever)**

Save the `FIXTURE` section as `fixtures/<name>.json`, then:

```bash
node test-fixture-replay.js                       # all fixtures
node test-fixture-replay.js fixtures/mine.json    # one
```

This rebuilds the captured markup in jsdom, loads the **real** provider file
into it, and asserts it still finds the turns and parses the command.

**Privacy:** the fixture keeps only the last 8 turns, truncates text to ~160
characters, and strips the composer's contents, so it is safe to paste into an
issue. Nothing is transmitted anywhere - it goes to your clipboard.

**Mutation-checked:** reintroducing the real turn-anchoring bug
(`div.px-3` instead of `div.flex.flex-col.gap-2`) makes the replayed fixture
fail 3 assertions, including "a command in the captured reply is parsed" - the
exact symptom behind *"Arena Agent did not respond in time"*.

## Self-update

`updater.py` fast-forwards a git-cloned install and reports what changed.

```bash
python3 updater.py          # check only (never modifies anything)
python3 updater.py apply    # fast-forward
python3 test_updater.py     # 20 assertions against real git repos
```

From the extension: **⬆ Check for updates** in the popup. It checks, applies,
then reloads the extension. The bridge still needs a manual restart — a process
cannot safely replace itself mid-tool-call.

It **never updates on its own**. The bridge reports available updates once at
startup and stops there: this drives your files and your Roblox place, so a
surprise change mid-session is not acceptable.

Refusals, which matter more than the happy path:

| Situation | Behaviour |
| --- | --- |
| Uncommitted changes | refuses, names the files, changes nothing |
| Local commits ahead of origin | refuses (no fast-forward possible) |
| Not a git clone | reports it and carries on running |
| No network / git missing | reports it and carries on running |

## HTTP API — testing the bridge without a browser

The WebSocket API can only be driven by the extension, so the bridge could not
be exercised from a terminal, from CI, or from any machine without Chrome. That
is precisely what turned every provider bug into a guess-and-check loop. The
same calls are now available over plain HTTP.

```bash
curl localhost:17613/healthz        # liveness (open, no token - a PaaS polls it)
curl localhost:17613/status         # target, servers, tool counts
curl localhost:17613/tools          # full tool list with schemas
curl -G --data-urlencode 'name=read_file' \
     --data-urlencode 'args={"path":"note.txt"}' \
     localhost:17613/call           # run a tool
open  http://localhost:17613/       # human-readable status page
```

With `ZS_BRIDGE_TOKEN` set, everything except `/healthz` needs
`?token=...` or `Authorization: Bearer ...`.

### Why `/call` uses a query string, not a POST body

`websockets`' `process_request` hook is **never invoked** for a request that
carries a body — the library cannot parse one, and curl simply sees the
connection close (exit 52). Verified directly against websockets 17. A query
string reaches the handler reliably, so that is the interface.

```bash
python3 test_http_api.py    # 26 assertions against a real running bridge
```
