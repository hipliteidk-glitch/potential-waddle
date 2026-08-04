// SPDX-License-Identifier: GPL-3.0-or-later
// test-arena-agent.js - the Arena Agent Mode provider's DOM logic.
//
// Built from live captures of arena.ai/agent. The critical property is the
// COMPOSER COLLISION: the TipTap composer itself carries `prose`, so a naive
// `.prose` lookup returns the input box and the agent would read its own
// typing as an assistant reply, parse commands from it, and feed results back
// into it. These tests pin that guard and the user/assistant discriminator.
//
// Run:  node test-arena-agent.js
const fs = require("fs");
const path = require("path");

let pass = 0, fail = 0;
const ok = (name, cond, extra) => {
  if (cond) { console.log("PASS ", name); pass++; }
  else { console.log("FAIL ", name, extra === undefined ? "" : "\n      " + extra); fail++; }
};

// ── the real class strings captured from /agent ────────────────────────────
const COMPOSER_CLS =
  "tiptap ProseMirror prose max-w-none focus:outline-none bg-surface-secondary " +
  "max-h-[40vh] min-h-[32px] overflow-y-auto p-1 md:min-h-[80px] md:p-3";
const BODY_CLS =
  "prose prose-pre:bg-transparent prose-pre:p-0 text-wrap break-words prose-base body-base";
const USER_GPARENT = "px-3 text-text-primary body-base py-2";
const ASSISTANT_GPARENT = "px-3 pb-3";

// ── minimal element stand-ins ──────────────────────────────────────────────
function el(cls, { editable = false, gparentCls = null, text = "" } = {}) {
  const node = {
    className: cls,
    textContent: text,
    isContentEditable: editable,
    classList: { contains: (c) => cls.split(/\s+/).includes(c) },
    offsetParent: {},
    closest: (sel) => (editable && sel.includes("contenteditable") ? node : null),
  };
  if (gparentCls !== null) {
    node.parentElement = { parentElement: { className: gparentCls } };
  }
  return node;
}

// ── the logic under test, mirroring providers/arena-agent.js ───────────────
const isComposerNode = (e) =>
  !!e && (e.classList.contains("tiptap") || e.classList.contains("ProseMirror") ||
          e.isContentEditable || !!e.closest('[contenteditable="true"]'));
const isTurnBody = (e) =>
  !!e && e.classList && e.classList.contains("prose") && !isComposerNode(e);
const roleOf = (e) => {
  const g = e && e.parentElement && e.parentElement.parentElement;
  const c = (g && g.className) || "";
  return /text-text-primary/.test(c) && /py-2/.test(c) ? "user" : "assistant";
};

// ── the collision ──────────────────────────────────────────────────────────
const composer = el(COMPOSER_CLS, { editable: true });
ok("the composer is NOT treated as a turn body", !isTurnBody(composer));
ok("the composer IS recognised as the composer", isComposerNode(composer));

const body = el(BODY_CLS, { gparentCls: ASSISTANT_GPARENT, text: "hi" });
ok("a real reply IS a turn body", isTurnBody(body));
ok("a real reply is not the composer", !isComposerNode(body));

// ── user vs assistant, against the captured transcript ─────────────────────
const transcript = [
  el(BODY_CLS, { gparentCls: USER_GPARENT, text: "Oo" }),
  el(BODY_CLS, { gparentCls: ASSISTANT_GPARENT, text: "Hey! Looks like that message may have" }),
  el(BODY_CLS, { gparentCls: USER_GPARENT, text: "O" }),
  el(BODY_CLS, { gparentCls: ASSISTANT_GPARENT, text: "Still just a quick one!" }),
];
const roles = transcript.map(roleOf);
ok("roles alternate user/assistant as captured",
   roles.join() === "user,assistant,user,assistant", roles.join());
ok("assistant turns counted correctly", roles.filter((r) => r === "assistant").length === 2);
ok("user turns counted correctly", roles.filter((r) => r === "user").length === 2);

// with the composer mixed in, it must never be counted
const withComposer = [...transcript, composer];
const bodies = withComposer.filter(isTurnBody);
ok("the composer is excluded from the turn list", bodies.length === 4, `${bodies.length}`);
const lastAssistant = bodies.filter((b) => roleOf(b) === "assistant").pop();
ok("lastAssistant is the newest reply, not the composer",
   lastAssistant.textContent === "Still just a quick one!", lastAssistant.textContent);

// ── DOM order is chronological here (NOT reversed like /text/direct) ───────
ok("first turn is the oldest", bodies[0].textContent === "Oo");

// ── the provider file itself ───────────────────────────────────────────────
const src = fs.readFileSync(path.join(__dirname, "providers", "arena-agent.js"), "utf8");
ok("provider guards the composer collision", src.includes("isComposerNode"));
ok("provider documents that there is no message list", /NO message list/i.test(src));
ok("provider does NOT reverse DOM order", !/\.reverse\(\)/.test(src));
ok("provider declares no vision (image tools stay hidden)",
   /supportsVision:\s*false/.test(src));
ok("provider warns it is experimental", /experimental/i.test(src));
ok("provider uses execCommand for the contenteditable",
   src.includes("insertText"));
ok("provider exports the interface the core needs",
   ["allItems", "assistantCount", "lastAssistant", "typeAndSend", "getEditor",
    "installSendHooks", "streamLen", "snapshot"].every((k) => src.includes(k)));

// ── manifest wiring: the two Arena providers must NEVER share a document ───
// Both files declare `const ZSProvider`; loading both would throw
// "Identifier 'ZSProvider' has already been declared" and neither would run.
{
  const man = JSON.parse(fs.readFileSync(path.join(__dirname, "manifest.json"), "utf8"));
  const arenaBlocks = man.content_scripts.filter((cs) =>
    cs.matches.some((m) => m.includes("arena.ai")));
  const direct = arenaBlocks.find((cs) => cs.js.includes("providers/arena.js"));
  const agent = arenaBlocks.find((cs) => cs.js.includes("providers/arena-agent.js"));
  ok("both Arena providers are registered", !!direct && !!agent);
  ok("the agent provider is scoped to /agent",
     !!agent && agent.matches.every((m) => m.includes("/agent")));
  ok("the direct provider EXCLUDES /agent",
     !!direct && (direct.exclude_matches || []).some((m) => m.includes("/agent")));
  ok("they never both load on /agent",
     !!direct && !!agent &&
     (direct.exclude_matches || []).some((m) => m === "https://arena.ai/agent/*"));
  ok("the agent block loads the core too",
     !!agent && agent.js.includes("core/main.js") && agent.js.includes("core/config.js"));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
