// SPDX-License-Identifier: GPL-3.0-or-later
const KOFI_URL = "https://ko-fi.com/sebattfg";
const SUPPORTED_HOSTS = [
  "chat.deepseek.com", "deepseek.com", "gemini.google.com", "www.kimi.com", "kimi.com",
  "chat.z.ai", "chat.qwen.ai", "arena.ai", "www.meta.ai", "meta.ai",
];
const DEFAULT_AI_URL = "https://chat.deepseek.com/";

document.getElementById("ver").textContent = `v${chrome.runtime.getManifest().version}`;

function render(s) {
  const dot = document.getElementById("dot");
  const state = document.getElementById("state");
  const tools = document.getElementById("tools");
  const servers = document.getElementById("servers");
  const list = s.servers || [];
  const up = list.filter((x) => x.alive).length;
  const mcpOk = s.connected && (s.mcpAlive || up > 0 || s.tools > 0);
  const studioOff = mcpOk && s.studio === false; // MCP up but no Studio attached
  const ok = mcpOk && !studioOff;
  dot.className = "dot " + (s.connected ? (ok ? "on" : "warn") : "");
  state.textContent = s.connected
    ? (ok ? "Connected · Roblox Studio ready"
        : studioOff ? "Studio not connected · enable the MCP server in Studio"
        : "Bridge OK · open Roblox Studio")
    : "Bridge offline";
  tools.textContent = s.connected ? `${s.tools || 0} tools available` : "Run bridge.py";
  servers.textContent = s.connected
    ? list.map((x) => `${x.alive ? "●" : "○"} ${x.id} (${x.alive ? x.tools + " tools" : "down"})`).join("\n")
    : "";
}

function refresh() {
  chrome.runtime.sendMessage({ type: "status" }, (s) => s && render(s));
}

document.getElementById("reconnect").addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "reconnect" }, () => setTimeout(refresh, 600));
});
document.getElementById("restart").addEventListener("click", (e) => {
  e.target.textContent = "Restarting…";
  chrome.runtime.sendMessage({ type: "restart_mcp" }, () => {
    e.target.textContent = "⟳ Restart Roblox server";
    setTimeout(refresh, 600);
  });
});
document.getElementById("kofi").addEventListener("click", () => {
  chrome.tabs.create({ url: KOFI_URL });
});
document.getElementById("settings").addEventListener("click", () => {
  // Same mechanism as the Ko-fi button (chrome.tabs), but tries the in-page
  // panel on an already-open supported AI tab first, so opening it doesn't
  // require a conversation to already be started there.
  chrome.tabs.query({}, (tabs) => {
    const active = tabs.find((t) => t.active && t.url && SUPPORTED_HOSTS.some((h) => t.url.includes(h)));
    const anySupported = active || tabs.find((t) => t.url && SUPPORTED_HOSTS.some((h) => t.url.includes(h)));
    if (anySupported) {
      chrome.tabs.sendMessage(anySupported.id, { type: "zs-open-menu" });
      chrome.tabs.update(anySupported.id, { active: true });
    } else {
      chrome.tabs.create({ url: DEFAULT_AI_URL });
    }
  });
});

chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === "zs-status") render(msg);
});
refresh();
setInterval(refresh, 2000);

// ── Bridge endpoint panel ──────────────────────────────────────────────────
// The bridge is normally local, but it can run elsewhere (a container or a
// Railway deploy), which requires a token. Editing it here avoids asking
// anyone to hand-edit background.js.
const epPanel = document.getElementById("endpoint-panel");
const epUrl = document.getElementById("ep-url");
const epToken = document.getElementById("ep-token");
const epWarn = document.getElementById("ep-warn");

function showWarn(text) {
  epWarn.textContent = text || "";
  epWarn.style.display = text ? "" : "none";
}

document.getElementById("endpoint-toggle").addEventListener("click", () => {
  const open = epPanel.style.display !== "none";
  epPanel.style.display = open ? "none" : "";
  if (!open) {
    chrome.runtime.sendMessage({ type: "get-endpoint" }, (r) => {
      if (!r || !r.ok) return;
      epUrl.value = r.url || "";
      // Never render the saved secret back into the DOM; just say it is set.
      epToken.value = "";
      epToken.placeholder = r.hasToken ? "token saved - type to replace" : "token (remote bridges only)";
      showWarn(r.warning);
    });
  }
});

document.getElementById("ep-save").addEventListener("click", () => {
  const payload = { type: "set-endpoint", url: epUrl.value };
  // Empty box = keep the existing token, so saving a URL doesn't wipe it.
  if (epToken.value.trim()) payload.token = epToken.value.trim();
  chrome.runtime.sendMessage(payload, (r) => {
    if (!r || !r.ok) { showWarn((r && r.error) || "could not save"); return; }
    epToken.value = "";
    showWarn(r.warning);
    refresh();
  });
});

document.getElementById("ep-reset").addEventListener("click", () => {
  chrome.runtime.sendMessage(
    { type: "set-endpoint", url: "ws://127.0.0.1:17613", token: "" }, (r) => {
      if (r && r.ok) { epUrl.value = r.url; epToken.value = ""; showWarn(""); refresh(); }
    });
});
