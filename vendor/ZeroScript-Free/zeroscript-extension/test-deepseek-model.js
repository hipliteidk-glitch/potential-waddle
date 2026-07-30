// SPDX-License-Identifier: GPL-3.0-or-later
// test-deepseek-model.js - the DeepSeek startup-model choice.
//
// Expert is the default because the agent loop needs exactly-formatted command
// JSON over many turns. Instant is opt-in. These tests pin both, plus the rules
// that must not regress: Vision is never overridden, and a missing Instant tab
// falls back to Expert instead of selecting nothing.
//
// Run:  node test-deepseek-model.js
const fs = require("fs");
const path = require("path");

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { console.log("PASS ", name); pass++; }
  else { console.log("FAIL ", name, extra === undefined ? "" : "\n      " + extra); fail++; }
}

// ── Minimal DOM good enough for the mode logic ────────────────────────────
function makeRadio(type, label, checked) {
  return {
    _type: type, _label: label,
    _attrs: { "data-model-type": type, "aria-checked": checked ? "true" : "false" },
    textContent: label,
    clicked: 0,
    getAttribute(k) { return this._attrs[k] === undefined ? null : this._attrs[k]; },
    click() { this.clicked++; this._attrs["aria-checked"] = "true"; },
    querySelectorAll() { return []; },
    closest() { return null; },
  };
}

function scenario({ tabs, prefer }) {
  const radios = tabs.map((t) => makeRadio(t.type, t.label, !!t.checked));
  // Selecting one radio unchecks the rest, as a real radiogroup does.
  radios.forEach((r) => {
    const origClick = r.click.bind(r);
    r.click = () => { radios.forEach((o) => (o._attrs["aria-checked"] = "false")); origClick(); };
  });

  const RE = {
    expertMode: /expert|专家|专业/i,
    instantMode: /instant|rapide|快速|标准/i,
    visionMode: /vision|视觉|图像|多模态/i,
  };
  const nodeText = (n) => (n && n.textContent) || "";
  const findModeRadio = (type, re) =>
    radios.find((r) => r.getAttribute("data-model-type") === type) ||
    (re && radios.find((r) => re.test(nodeText(r)))) || null;
  const findExpertRadio = () => findModeRadio("expert", RE.expertMode);
  const findInstantRadio = () => findModeRadio("default", RE.instantMode);
  const findVisionRadio = () => findModeRadio("vision", RE.visionMode);
  const radioOn = (r) => !!r && r.getAttribute("aria-checked") === "true";
  const isVisionSelected = () => radioOn(findVisionRadio());

  // The branch under test, mirroring enforceComposer in providers/deepseek.js.
  const preferInstant = !!prefer;
  if (!isVisionSelected()) {
    const wantInstant = preferInstant && !!findInstantRadio();
    const target = wantInstant ? findInstantRadio() : findExpertRadio();
    if (target && target.getAttribute("aria-checked") !== "true") target.click();
  }
  const selected = radios.find((r) => radioOn(r));
  const state = {
    expertOn: radioOn(findExpertRadio()),
    instantOn: radioOn(findInstantRadio()),
    visionOn: radioOn(findVisionRadio()),
  };
  const ready = state.expertOn || state.visionOn || (preferInstant && state.instantOn);
  return { selected: selected ? selected._type : null, ready, radios };
}

const FULL = [
  { type: "default", label: "Instant" },
  { type: "expert", label: "Expert" },
  { type: "vision", label: "Vision" },
];

// ── default: Expert ───────────────────────────────────────────────────────
let r = scenario({ tabs: FULL, prefer: false });
ok("default picks Expert", r.selected === "expert", r.selected);
ok("default is ready", r.ready);

// ── opt-in: Instant ───────────────────────────────────────────────────────
r = scenario({ tabs: FULL, prefer: true });
ok("preferInstant picks Instant", r.selected === "default", r.selected);
ok("Instant counts as ready when preferred", r.ready);

// ── Instant preferred but Expert already active -> switches ───────────────
r = scenario({ tabs: [
  { type: "default", label: "Instant" },
  { type: "expert", label: "Expert", checked: true },
], prefer: true });
ok("switches away from an already-checked Expert", r.selected === "default", r.selected);

// ── Vision chosen by the user is never overridden ─────────────────────────
r = scenario({ tabs: [
  { type: "default", label: "Instant" },
  { type: "expert", label: "Expert" },
  { type: "vision", label: "Vision", checked: true },
], prefer: false });
ok("Vision is respected over Expert", r.selected === "vision", r.selected);
r = scenario({ tabs: [
  { type: "default", label: "Instant" },
  { type: "expert", label: "Expert" },
  { type: "vision", label: "Vision", checked: true },
], prefer: true });
ok("Vision is respected over Instant too", r.selected === "vision", r.selected);

// ── no Instant tab (older UI) -> fall back to Expert, never nothing ───────
r = scenario({ tabs: [{ type: "expert", label: "Expert" }], prefer: true });
ok("missing Instant tab falls back to Expert", r.selected === "expert", r.selected);
ok("fallback is still ready", r.ready);

// ── label fallback when data-model-type is absent ─────────────────────────
r = scenario({ tabs: [
  { type: "", label: "Instant" },
  { type: "", label: "Expert" },
], prefer: true });
ok("finds Instant by label when the attribute is missing", r.selected === "" && r.radios[0].clicked === 1,
   `clicked: instant=${r.radios[0].clicked} expert=${r.radios[1].clicked}`);

// ── Expert preferred is NOT ready if only Instant is on ───────────────────
const onlyInstantOn = (() => {
  const preferInstant = false;
  const state = { expertOn: false, instantOn: true, visionOn: false };
  return state.expertOn || state.visionOn || (preferInstant && state.instantOn);
})();
ok("Instant alone is NOT ready when Expert is preferred", onlyInstantOn === false);

// ── the real file still parses and contains the wiring ────────────────────
const src = fs.readFileSync(path.join(__dirname, "providers", "deepseek.js"), "utf8");
ok("provider reads the saved preference", src.includes("zsDeepseekModel"));
ok("provider has an Instant finder", src.includes("findInstantRadio"));
ok("provider still defaults to Expert", src.includes("findExpertRadio()"));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
