// SPDX-License-Identifier: GPL-3.0-or-later
// test-dola-dom.js - the REAL Dola provider against the REAL captured DOM.
//
// Markup reproduced from live captures of dola.com/chat/<id>, including the
// three things that would otherwise have been guessed wrong:
//   1. the role marker is justify-end on a DESCENDANT, not an ancestor
//   2. the last .v_list_row is a SPACER with no data-observe-row
//   3. Semi keeps a second, class-less <textarea> offscreen for autosize
//
// Run:  node test-dola-dom.js      (needs: npm install --no-save jsdom)
const fs = require("fs");
const path = require("path");
const vm = require("vm");

let JSDOM;
try { ({ JSDOM } = require("jsdom")); }
catch { console.log("SKIP  jsdom not installed - run: npm install --no-save jsdom"); process.exit(0); }

let pass = 0, fail = 0;
const ok = (n, c, extra) => {
  if (c) { console.log("PASS ", n); pass++; }
  else { console.log("FAIL ", n, extra === undefined ? "" : "\n      " + extra); fail++; }
};

// Real class strings from the capture (trimmed but structurally faithful).
const ASSIST_FLEX = "flex flex-row w-full w-full max-w-full s-font-base p-0 bg-transparent group";
const USER_FLEX = "flex flex-row w-full justify-end w-full max-w-full s-font-base p-0 bg-transparent";
const INNER = 'pl-8 pr-0 w-full';

const row = (id, flexCls, text) => `
  <div class=" v_list_row" data-observe-row="${id}" style="width:100%">
    <div class="${INNER}"><div class="my-0 w-full mx-auto"><div class="w-full inner-item-BjaxFt">
      <div class="w-full"><div class="${flexCls}">
        <div class="flex flex-col flex-grow max-w-full min-w-0">${text}</div>
      </div></div>
    </div></div></div>
  </div>`;

const HTML = `<!doctype html><html><body>
<div class="scroller v_list_scroller-BxcoIX"><div class="scroller_content"><div class="list_items">
  <!-- TOP spacer, seen live. Given an id so ONLY the indicator check excludes
       it - otherwise the two guards mask each other. -->
  <div class="v_list_row" data-observe-row="block_spacer_top" style="width:100%;z-index:1">
    <div><div class="v_list_top_indicator-OESqxW"></div><div class="${INNER}">
      <div class="w-full top-item-bAlX0F"></div></div></div>
  </div>
  ${row("block_1275552801841681", USER_FLEX, "O")}
  ${row("block_1275552801841682", ASSIST_FLEX, 'It looks like you only typed "O" - did you mean to send something?')}
  ${row("block_1276056118724113", USER_FLEX, "run list_commands please")}
  ${row("block_1276056118730513", ASSIST_FLEX, '<pre><code>{"command":"list_commands"}</code></pre>')}
  <!-- SPACER A: no data-observe-row (as captured) -->
  <div class="v_list_row" style="width:100%;z-index:1">
    <div><div class="v_list_bottom_indicator-nnTzdE"></div><div class="${INNER}">
      <div class="w-full bottom-item-ProfSp"></div></div></div>
  </div>
  <!-- SPACER B: same indicator but WITH an id, so only the indicator check
       can exclude it. Without this the two guards mask each other and a
       mutation removing either one still passes. -->
  <div class="v_list_row" data-observe-row="block_spacer_999" style="width:100%">
    <div><div class="v_list_bottom_indicator-nnTzdE"></div><div class="${INNER}">
      <div class="w-full bottom-item-ProfSp">   </div></div></div>
  </div>
</div></div></div>
<textarea></textarea>
<div class="container-kxxSU4 flex-1">
  <textarea class="semi-input-textarea semi-input-textarea-autosize"></textarea>
</div>
<button>Send</button>
</body></html>`;

const dom = new JSDOM(HTML, { url: "https://www.dola.com/chat/38416201189847313",
                              pretendToBeVisual: true });
// jsdom gives no layout; treat everything as laid out EXCEPT the bare mirror
// textarea, so the "pick the classed one" logic is genuinely exercised.
Object.defineProperty(dom.window.HTMLElement.prototype, "getClientRects", {
  // BOTH textareas are laid out. Semi's mirror is not hidden in practice, so
  // getEditor() must pick the right one by CLASS, not by visibility - an
  // earlier version of this stub hid the mirror and let a loose "textarea"
  // selector pass by accident.
  value() { return [{ width: 300, height: 40 }]; },
});
Object.defineProperty(dom.window.HTMLElement.prototype, "clientWidth", {
  get() { return this.tagName === "TEXTAREA" ? 200 : 400; },
});

const providerSrc = fs.readFileSync(
  path.join(__dirname, "providers", "dola.js"), "utf8");
const sandbox = {
  window: dom.window, document: dom.window.document,
  location: dom.window.location, navigator: dom.window.navigator,
  setTimeout, clearTimeout, console, Date,
  Event: dom.window.Event, InputEvent: dom.window.InputEvent,
  KeyboardEvent: dom.window.KeyboardEvent,
};
vm.createContext(sandbox);
vm.runInContext(providerSrc + "\n;globalThis.__P = ZSProvider;", sandbox);
const P = sandbox.__P;

ok("the real provider file loads", !!P && typeof P.allItems === "function");

// ── turns, and the spacer trap ─────────────────────────────────────────────
const items = P.allItems();
ok("allItems() finds the 4 real turns (spacer excluded)", items.length === 4,
   `found ${items.length}`);
ok("the bottom spacer is not a turn",
   !items.some((i) => i.querySelector('[class*="v_list_bottom_indicator"]')));
ok("the TOP spacer is not a turn (it carries an id, so only the indicator check saves us)",
   !items.some((i) => i.querySelector('[class*="v_list_top_indicator"]')));

// ── the role marker (on a DESCENDANT, not an ancestor) ─────────────────────
const users = items.filter(P.isUserItem);
const bots = items.filter(P.isAssistantItem);
ok("2 user turns via justify-end", users.length === 2, `${users.length}`);
ok("2 assistant turns", bots.length === 2, `${bots.length}`);
ok("assistantCount() agrees", P.assistantCount() === 2);
ok("the first turn is the user's 'O'", P.itemText(items[0]).trim() === "O",
   JSON.stringify(P.itemText(items[0]).trim()));
ok("the reply is classified assistant",
   /only typed/.test(P.itemText(items[1])) && P.isAssistantItem(items[1]));

// ── identity, which is what survives virtualisation ────────────────────────
ok("lastAssistantId() returns the stable row id",
   P.lastAssistantId() === "block_1276056118730513", P.lastAssistantId());
ok("lastAssistant() is the newest reply",
   /list_commands/.test(P.readAssistant()), P.readAssistant().slice(0, 40));
ok("reliableCounts is false (list is virtualised)", P.reliableCounts === false);

// ── the command must survive to the parser ─────────────────────────────────
const ZSParse = vm.runInNewContext(
  fs.readFileSync(path.join(__dirname, "core", "parser.js"), "utf8") + ";ZSParse",
  { console });
const calls = ZSParse.parseToolCalls(P.readAssistant());
ok("the real parser extracts the command from the real DOM",
   Array.isArray(calls) && calls.length === 1 && calls[0].tool === "list_commands",
   JSON.stringify(calls));

// ── composer: must pick the CLASSED textarea, not Semi's mirror ────────────
const ed = P.getEditor();
ok("getEditor() finds a textarea", !!ed && ed.tagName === "TEXTAREA");
ok("it is the CLASSED one, not the autosize mirror",
   !!ed && /semi-input-textarea/.test(ed.className), ed && ed.className);
ok("the composer is never counted as a turn",
   !items.some((i) => i.querySelector("textarea")));
ok("composerFrame() is outside the textarea",
   !!P.composerFrame() && P.composerFrame() !== ed);
ok("chatIsEmpty() is false with turns present", P.chatIsEmpty() === false);

// ── an empty / signed-out page ─────────────────────────────────────────────
const dom2 = new JSDOM(`<!doctype html><html><body>
  <textarea class="semi-input-textarea"></textarea>
  <button>Log In</button></body></html>`, { url: "https://www.dola.com/chat/" });
Object.defineProperty(dom2.window.HTMLElement.prototype, "getClientRects",
  { value() { return [{ width: 100, height: 20 }]; } });
const sb2 = {
  window: dom2.window, document: dom2.window.document,
  location: dom2.window.location, navigator: dom2.window.navigator,
  setTimeout, clearTimeout, console, Date,
  Event: dom2.window.Event, InputEvent: dom2.window.InputEvent,
  KeyboardEvent: dom2.window.KeyboardEvent,
};
vm.createContext(sb2);
vm.runInContext(providerSrc + "\n;globalThis.__P = ZSProvider;", sb2);
const P2 = sb2.__P;
ok("an empty chat reports 0 turns", P2.allItems().length === 0);
ok("isFreshChat() is true", P2.isFreshChat() === true);
ok("lastAssistant() is null", P2.lastAssistant() === null);
ok("signed out is reported as a mode warning",
   /log in/i.test(P2.modeWarning()), P2.modeWarning());

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
