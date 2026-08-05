// SPDX-License-Identifier: GPL-3.0-or-later
// providers/dola.js - the Dola (dola.com) provider.
//
// Exports the same ZSProvider interface as providers/deepseek.js; the core
// (core/main.js) is provider-agnostic.
//
// DOM notes - derived from live captures of /chat/<id> (2026-08), not guessed:
//
//  - NO message list element. There is no <ol>/<ul>/role=log; turns are rows
//    inside a VIRTUALISED scroller (.scroller.v_list_scroller-*). Rows are
//    REMOVED from the DOM when scrolled out of view, so assistantCount() can
//    DROP even as a new reply arrives. That is why lastAssistantId() below is
//    important: the core prefers node identity over counting when a provider
//    exposes it (core/main.js ~390), which is virtualisation-proof.
//
//  - A turn is div.v_list_row. Each carries a STABLE id attribute:
//        data-observe-row="block_1276056118724113"
//    Ideal for lastAssistantId().
//
//  - ROLE is NOT on an ancestor (an ancestor-only scan found nothing, and all
//    four sampled turns looked identical). It is on a DESCENDANT flex row:
//        user      -> "... flex flex-row w-full justify-end ..."
//        assistant -> same WITHOUT justify-end, and carries `group`
//    i.e. the user's bubble is right-aligned. Verified against a real
//    transcript: O / reply / O / reply classified correctly.
//
//  - The LAST .v_list_row is a SPACER, not a message: it has no
//    data-observe-row and contains .v_list_bottom_indicator-*. Counting it
//    would put every turn count permanently out by one.
//
//  - The composer is a real <textarea> (Semi Design: .semi-input-textarea),
//    NOT a contenteditable - so the native value setter path applies, like
//    Arena Direct rather than Arena Agent.
//
//  - A second, class-less <textarea> exists (an offscreen autosize mirror that
//    Semi uses to measure height). getEditor() must not pick it.
// eslint-disable-next-line no-unused-vars
const ZSProvider = (() => {
  "use strict";
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let diag = () => {};

  const S = {
    row: "div.v_list_row",
    rowId: "data-observe-row",
    // Virtualiser spacers. There is a TOP one as well as a bottom one
    // (v_list_top_indicator-*, v_list_bottom_indicator-*), and both are
    // .v_list_row with no data-observe-row. Matching only the bottom one left
    // the top spacer relying on the id check alone; match any *_indicator so
    // either guard is sufficient on its own.
    spacer: '[class*="v_list_top_indicator"], [class*="v_list_bottom_indicator"],'
          + ' [class*="top-item-"], [class*="bottom-item-"]',
    editor: "textarea.semi-input-textarea",
    scroller: '[class*="v_list_scroller"]',
    // Dola's UI is English/Chinese; match both for the send/stop controls.
    sendAria: /send|发送/i,
    stopAria: /stop|cancel|停止|取消/i,
    errorSurfaces:
      '[role="alert"],[class*="toast"],[class*="error"],[class*="semi-toast"]',
  };

  const vis = (e) => !!(e && e.getClientRects && e.getClientRects().length);
  const txt = (e) => (e && e.textContent ? e.textContent : "");

  // ── turns ─────────────────────────────────────────────────────────────────
  // A row counts only if it carries the id attribute: that excludes the
  // bottom spacer, which is a .v_list_row with no data-observe-row.
  const isTurnRow = (el) =>
    !!el && el.hasAttribute && el.hasAttribute(S.rowId) &&
    !el.querySelector(S.spacer) &&
    !el.querySelector("textarea, [contenteditable='true']");

  function allItems() {
    return [...document.querySelectorAll(S.row)].filter(isTurnRow);
  }

  // The role lives on a DESCENDANT flex row, not an ancestor: a user turn's
  // bubble is right-aligned with justify-end.
  const roleOf = (el) => {
    if (!el || !el.querySelector) return "assistant";
    const flex = el.querySelector('[class*="flex-row"]');
    const c = (flex && typeof flex.className === "string" ? flex.className : "") ||
              (typeof el.className === "string" ? el.className : "");
    return /\bjustify-end\b/.test(c) ? "user" : "assistant";
  };

  const isUserItem = (el) => isTurnRow(el) && roleOf(el) === "user";
  const isAssistantItem = (el) => isTurnRow(el) && roleOf(el) === "assistant";
  const itemText = (el) => txt(el);
  const classifyText = (el) => itemText(el);

  const assistantItems = () => allItems().filter(isAssistantItem);
  const assistantCount = () => assistantItems().length;
  const userCount = () => allItems().filter(isUserItem).length;
  const lastAssistant = () => {
    const a = assistantItems();
    return a.length ? a[a.length - 1] : null;
  };
  // Virtualisation-proof identity: the core prefers this over counting.
  const lastAssistantId = () => {
    const el = lastAssistant();
    return el ? el.getAttribute(S.rowId) || "" : "";
  };
  const readAssistant = (el) => itemText(el || lastAssistant());
  const snapshot = () => ({ a: assistantCount(), u: userCount() });

  // ── generation detection ──────────────────────────────────────────────────
  const allButtons = () => [...document.querySelectorAll("button")].filter(vis);
  const labelOf = (b) =>
    (b.getAttribute("aria-label") || b.getAttribute("title") || txt(b) || "").trim();
  const sendButton = () => allButtons().find((b) => S.sendAria.test(labelOf(b))) || null;
  const stopButton = () => {
    const send = sendButton();
    return allButtons().find((b) => b !== send && S.stopAria.test(labelOf(b))) || null;
  };

  // No streaming marker was observed, so fall back to growth of the reply
  // text, with a separate first-token budget: the row can exist before any
  // text arrives, and a single short idle window would call that "finished".
  const FIRST_TOKEN_MS = 45000;
  const IDLE_MS = 4000;
  let _max = -1, _at = 0, _item = null, _born = 0;
  function streamLen(item) {
    const el = item === undefined ? lastAssistant() : item;
    return txt(el).length;
  }
  function growing() {
    const el = lastAssistant();
    const len = streamLen(el);
    const now = Date.now();
    if (el !== _item) { _item = el; _max = len; _at = now; _born = now; return true; }
    if (len > _max) { _max = len; _at = now; return true; }
    if (_max <= 0) return now - _born < FIRST_TOKEN_MS;
    return now - _at < IDLE_MS;
  }
  const isGenerating = () => !!stopButton() || growing();
  const isHardGenerating = () => !!stopButton();
  const isBusyNow = () => isGenerating();

  // ── composer ──────────────────────────────────────────────────────────────
  // Semi keeps a second, CLASS-LESS textarea offscreen to measure autosize
  // height. Match the classed one only, and require it to be visible.
  const getEditor = () => {
    const all = [...document.querySelectorAll(S.editor)];
    return all.find(vis) || all[0] || null;
  };
  const editorText = () => {
    const e = getEditor();
    return e ? (e.value || "").trim() : "";
  };
  const chatIsEmpty = () => allItems().length === 0;
  const isFreshChat = () => chatIsEmpty() && !!getEditor();
  const composerFrame = () => {
    const e = getEditor();
    if (!e) return null;
    // Anchor OUTSIDE the input itself; walk up to a container that holds it.
    let n = e.parentElement;
    for (let i = 0; i < 4 && n && n.tagName !== "BODY"; i++) {
      if (n.tagName === "FORM") return n;
      if (n.clientWidth && n.clientWidth > (e.clientWidth || 0)) return n;
      n = n.parentElement;
    }
    return e.parentElement;
  };
  const barAnchor = () => composerFrame();
  const chipAnchor = () => lastAssistant();
  const chipAppend = true;
  const chipAtItemLevel = false;
  const findToolBlockSpot = () => lastAssistant();

  function setInputLock(on, msg) {
    const e = getEditor();
    if (!e) return;
    try {
      e.readOnly = !!on;
      if (msg) e.setAttribute("placeholder", msg);
    } catch {}
  }

  // React tracks the value internally; assigning .value directly is ignored on
  // submit. Use the native setter then fire input, as the other textarea-based
  // providers do.
  function setTextareaValue(el, value) {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype, "value").set;
    setter.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
  }

  async function waitFor(pred, timeout) {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      if (pred()) return true;
      await sleep(120);
    }
    return false;
  }

  async function typeAndSend(text) {
    const editor = getEditor();
    if (!editor) throw new Error("Dola input box not found");
    editor.focus();
    setTextareaValue(editor, text);
    const ready = () => {
      const b = sendButton();
      return !!b && !b.disabled && b.getAttribute("aria-disabled") !== "true";
    };
    await waitFor(ready, 30000);
    const b = sendButton();
    if (b) b.click();
    else editor.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Enter", bubbles: true, cancelable: true }));
    diag("dola.sent", { len: (text || "").length });
    return true;
  }

  function stopGeneration() {
    const b = stopButton();
    if (b) { try { b.click(); return true; } catch {} }
    return false;
  }

  // ── environment ───────────────────────────────────────────────────────────
  // Every capture so far showed a visible "Log In" control. Signed out, the
  // transcript may not render at all, so say so rather than fail obscurely.
  const signedOut = () =>
    [...document.querySelectorAll("button, a")].some((b) =>
      /^(log ?in|sign ?in|登录|登陸)$/i.test(txt(b).trim()));

  function modeWarning() {
    if (signedOut() && chatIsEmpty())
      return "Log in to <b>Dola</b> first - signed out, the chat is not available.";
    return "";
  }
  const captchaPresent = () => false;
  const overlayBlocking = () => false;
  const enforceComposer = () => ({ ready: !!getEditor() });
  async function ensureComposerReady() {
    const ok = await waitFor(() => !!getEditor(), 15000);
    return { ready: ok };
  }

  function scanError() {
    for (const n of document.querySelectorAll(S.errorSurfaces)) {
      if (!vis(n)) continue;
      const t = txt(n).trim();
      if (t) return t.slice(0, 300);
    }
    return "";
  }
  const isBusyMsg = (t) => /rate limit|too many requests|try again|请稍后/i.test(t || "");
  const isTooLongMsg = (t) => /too long|maximum context|token limit|过长/i.test(t || "");
  const turnHalted = () => false;
  const findContinueBtn = () => null;
  const clickContinueBtn = () => false;

  const attachImages = async () => false;
  const clearAttachments = () => {};

  const conversationKey = () => location.pathname;

  function installSendHooks(handlers) {
    document.addEventListener("keydown", (e) => {
      if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
      const editor = getEditor();
      if (!editor || e.target !== editor) return;
      if (editorText() === "") return;
      if (handlers.isBlocked()) return;
      if (!handlers.isStarted()) {
        if (!chatIsEmpty()) return;
        handlers.onBlockedAttempt();
        return;
      }
      handlers.onUserMessage(snapshot());
    }, true);
  }

  return {
    id: "dola",
    displayName: "Dola",
    supportsVision: false,
    // FALSE: the list is virtualised, so a count can drop as rows unmount.
    // The core then leans on lastAssistantId() for "is there a new reply",
    // which is identity-based and survives virtualisation.
    reliableCounts: false,
    timings: { NO_TURN_GRACE: 30000, IDLE_MS: 8000 },
    init({ diag: d } = {}) { if (d) diag = d; },
    allItems, isUserItem, isAssistantItem, itemText, classifyText,
    assistantCount, userCount, lastAssistant, lastAssistantId, readAssistant,
    streamLen, snapshot,
    getEditor, editorText, chatIsEmpty, isFreshChat, composerFrame, barAnchor,
    setInputLock, typeAndSend, stopGeneration,
    isGenerating, isBusyNow, isHardGenerating,
    enforceComposer, ensureComposerReady, modeWarning, captchaPresent,
    overlayBlocking, turnHalted, findContinueBtn, clickContinueBtn,
    chipAnchor, chipAppend, chipAtItemLevel, findToolBlockSpot,
    scanError, isBusyMsg, isTooLongMsg,
    attachImages, clearAttachments, conversationKey,
    installSendHooks,
  };
})();
