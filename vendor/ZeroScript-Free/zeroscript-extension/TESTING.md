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
