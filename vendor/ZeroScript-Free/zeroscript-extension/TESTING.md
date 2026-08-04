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
