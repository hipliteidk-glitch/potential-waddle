# SPDX-License-Identifier: GPL-3.0-or-later
# script_server.py
# ──────────────────────────────────────────────────────────────────────────
#  "No MCP" tools for the ZeroScript bridge.
#
#  Upstream ZeroScript can only talk to MCP servers: every target must speak
#  JSON-RPC over stdio (initialize / tools/list / tools/call). That is a lot of
#  ceremony when all you want is "let the AI run these three commands".
#
#  A ScriptClient lets you declare tools DIRECTLY in config.json as ordinary
#  shell commands. No MCP server, no JSON-RPC, no protocol to implement:
#
#    "servers": {
#      "shell": {
#        "type": "script",
#        "tools": [
#          {
#            "name": "list_files",
#            "description": "List files in a folder.",
#            "params": {"path": {"type": "string", "description": "folder"}},
#            "run": ["ls", "-la", "{path}"]
#          }
#        ]
#      }
#    }
#
#  It is deliberately duck-type compatible with MCPClient, so MCPManager, the
#  status probes and the WebSocket API cannot tell the difference - a script
#  server and a real MCP server can even run side by side.
#
#  SAFETY: "run" is a LIST (argv), executed WITHOUT a shell, so there is no
#  string interpolation into `sh -c` and therefore no shell-injection surface
#  from a model-supplied argument. A placeholder only ever becomes ONE argv
#  element. If you genuinely want a shell pipeline, set "shell": true on that
#  tool and accept the risk - it is off by default.
# ──────────────────────────────────────────────────────────────────────────
from __future__ import annotations

import json
import os
import subprocess
import threading
import time

# Placeholder syntax in a "run" entry: {param_name}
_PLACEHOLDER_OPEN = "{"
_PLACEHOLDER_CLOSE = "}"

DEFAULT_TIMEOUT = 60
MAX_OUTPUT = 60000  # chars of combined stdout/stderr handed back to the model


def _substitute(token: str, args: dict, used: set):
    """Replace {name} placeholders in ONE argv token.

    Returns the token with placeholders filled. A token that is exactly one
    placeholder ("{path}") and whose value is a list expands to several argv
    entries; the caller flattens that. Missing values become "".
    """
    if (token.startswith(_PLACEHOLDER_OPEN) and token.endswith(_PLACEHOLDER_CLOSE)
            and token.count(_PLACEHOLDER_OPEN) == 1):
        key = token[1:-1]
        used.add(key)
        val = args.get(key, "")
        if isinstance(val, list):
            return [str(v) for v in val]
        return [str(val)]
    # Inline placeholders inside a bigger token, e.g. "--path={path}".
    out = token
    for key, val in args.items():
        needle = _PLACEHOLDER_OPEN + key + _PLACEHOLDER_CLOSE
        if needle in out:
            used.add(key)
            out = out.replace(needle, "" if val is None else str(val))
    return [out]


class ScriptTool:
    def __init__(self, spec: dict):
        self.name = (spec.get("name") or "").strip()
        if not self.name:
            raise ValueError("every script tool needs a 'name'")
        self.description = spec.get("description") or f"Run the '{self.name}' command."
        self.params = spec.get("params") or {}
        run = spec.get("run")
        if isinstance(run, str):
            # A bare string is only allowed with shell:true - otherwise we would
            # have to guess at word splitting, which is exactly how quoting bugs
            # and injection holes get in.
            if not spec.get("shell"):
                raise ValueError(
                    f"tool '{self.name}': \"run\" must be a LIST of arguments "
                    f"(e.g. [\"ls\", \"-la\", \"{{path}}\"]). Use \"shell\": true only if "
                    f"you really want a shell string.")
            self.run = run
        elif isinstance(run, list) and run:
            self.run = [str(x) for x in run]
        else:
            raise ValueError(f"tool '{self.name}': missing a non-empty \"run\"")
        self.shell = bool(spec.get("shell"))
        # cwd may reference an env var, e.g. "{ZS_WORKSPACE}" or "$HOME/zs", so
        # one config file works across machines (and Termux's odd home path).
        self.cwd = spec.get("cwd")
        self.env = spec.get("env") or {}
        self.timeout = float(spec.get("timeout") or DEFAULT_TIMEOUT)

    def schema(self):
        """The MCP-shaped tool descriptor the extension/model consumes."""
        props = {}
        required = []
        for key, meta in self.params.items():
            if isinstance(meta, str):
                meta = {"type": "string", "description": meta}
            meta = dict(meta or {})
            if meta.pop("required", False):
                required.append(key)
            meta.setdefault("type", "string")
            props[key] = meta
        schema = {"type": "object", "properties": props}
        if required:
            schema["required"] = required
        return {"name": self.name, "description": self.description,
                "inputSchema": schema}

    def resolved_cwd(self):
        """Expand env vars / ~ in cwd. {NAME} is read from the environment too,
        so a config can say {ZS_WORKSPACE} without hardcoding a phone path."""
        if not self.cwd:
            return None
        path = str(self.cwd)
        for key, val in os.environ.items():
            path = path.replace("{" + key + "}", val)
        path = os.path.expanduser(os.path.expandvars(path))
        # An unresolved {PLACEHOLDER} means the variable is not set; fall back to
        # the process cwd rather than trying to chdir into a literal "{X}".
        if "{" in path and "}" in path:
            return None
        return path or None

    def _defaults(self):
        """Per-parameter "default" values from the schema, applied when the model
        omits an optional argument. Without this, `grep {pattern} {path}` with no
        path would drop the argument and grep would read stdin forever."""
        out = {}
        for key, meta in (self.params or {}).items():
            if isinstance(meta, dict) and meta.get("default") is not None:
                out[key] = meta["default"]
        return out

    def build_argv(self, args: dict):
        used = set()
        merged = dict(self._defaults())
        merged.update({k: v for k, v in (args or {}).items()
                       if v is not None and v != ""})
        args = merged
        if self.shell:
            cmd = self.run
            if isinstance(cmd, list):
                cmd = " ".join(cmd)
            for key, val in args.items():
                cmd = cmd.replace(_PLACEHOLDER_OPEN + key + _PLACEHOLDER_CLOSE,
                                  "" if val is None else str(val))
            return cmd, used
        argv = []
        for token in self.run:
            argv.extend(_substitute(token, args, used))
        # Drop empty trailing args produced by an omitted optional placeholder,
        # so `grep {pattern} {path}` with no path doesn't pass a stray "".
        while argv and argv[-1] == "":
            argv.pop()
        return argv, used

    def execute(self, args: dict, timeout=None):
        argv, _ = self.build_argv(args or {})
        env = dict(os.environ)
        env.update({str(k): str(v) for k, v in self.env.items()})
        try:
            res = subprocess.run(
                argv, shell=self.shell, cwd=self.resolved_cwd(), env=env,
                capture_output=True, text=True,
                # Detach stdin. With no terminal attached, anything that reads
                # stdin (an interactive prompt, `grep` with no file operand)
                # would hang until the timeout instead of returning.
                stdin=subprocess.DEVNULL,
                timeout=float(timeout or self.timeout), errors="replace")
        except subprocess.TimeoutExpired:
            raise TimeoutError(
                f"'{self.name}' timed out after {timeout or self.timeout}s.")
        except FileNotFoundError:
            prog = argv if isinstance(argv, str) else (argv[0] if argv else "?")
            raise RuntimeError(
                f"'{self.name}' could not run: command not found ({prog}). "
                f"Check the \"run\" entry in config.json.")
        except PermissionError:
            raise RuntimeError(f"'{self.name}' could not run: permission denied.")
        out = (res.stdout or "").strip()
        err = (res.stderr or "").strip()
        # A non-zero exit is reported to the MODEL as an error string (so it can
        # adapt) rather than raised, unless there is no output at all to explain
        # it - matching how a real MCP tool surfaces a failed operation.
        if res.returncode != 0:
            detail = err or out or f"exit code {res.returncode}"
            raise RuntimeError(f"'{self.name}' failed (exit {res.returncode}): {detail}"[:MAX_OUTPUT])
        text = out
        if err:
            text = (text + "\n[stderr] " + err).strip()
        if not text:
            text = f"(ok, '{self.name}' produced no output)"
        return text[:MAX_OUTPUT]


class ScriptClient:
    """Duck-type twin of MCPClient backed by plain commands (no MCP at all).

    Only the surface MCPManager / the probes actually use is implemented; the
    crash-loop and Studio-forensics attributes exist so the shared supervision
    code can read them without special-casing this class.
    """

    def __init__(self, server_id, spec):
        self.id = server_id
        self.spec = spec or {}
        self.command = f"(script: {len(self.spec.get('tools') or [])} tools)"
        self.args = []
        self.env = self.spec.get("env") or {}
        self.call_lock = threading.Lock()
        self.start_lock = threading.Lock()
        self.tools = {}
        self.tools_cache = []
        self._alive = False
        # Fields the shared supervisor/diagnostics read on every client.
        self.last_exit = None
        self.stderr_tail = []
        self.restart_times = []
        self.loop_warned_at = 0.0
        self.start_error = None
        self.saw_foreign_ws_host = False
        self.proc = None

    # ── lifecycle ─────────────────────────────────────────────────────────
    def start(self):
        with self.start_lock:
            self.tools = {}
            errors = []
            for raw in (self.spec.get("tools") or []):
                try:
                    t = ScriptTool(raw)
                except Exception as e:
                    errors.append(str(e))
                    continue
                self.tools[t.name] = t
            self.tools_cache = [t.schema() for t in self.tools.values()]
            if errors:
                self.start_error = "; ".join(errors)
                self.stderr_tail = errors[-5:]
            else:
                self.start_error = None
                self.stderr_tail = []
            # A script server with no VALID tools is useless; report it as not
            # alive so the usual "0 tools / offline" diagnostics kick in.
            self._alive = bool(self.tools)
            return self.tools_cache

    def is_alive(self):
        return self._alive

    def restart(self):
        self._alive = False
        return self.start()

    def stop(self):
        self._alive = False

    # ── tools ─────────────────────────────────────────────────────────────
    def refresh_tools(self, timeout=20):
        if not self._alive:
            self.start()
        return self.tools_cache

    def call_tool(self, name, arguments, timeout):
        """Returns {"text":..., "images":[]} or raises - same as MCPClient."""
        with self.call_lock:
            if not self._alive:
                self.start()
            tool = self.tools.get(name)
            if tool is None:
                raise RuntimeError(f"unknown tool '{name}' on script server '{self.id}'")
            text = tool.execute(arguments or {}, timeout=timeout)
            return {"text": text, "images": []}

    def probe_text(self, tool_name):
        """Best-effort probe used by the status layer. Never raises."""
        tool = self.tools.get(tool_name)
        if tool is None or not self._alive:
            return None
        if not self.call_lock.acquire(blocking=False):
            return None
        try:
            return tool.execute({}, timeout=min(8, tool.timeout))
        except Exception:
            return None
        finally:
            self.call_lock.release()


def looks_like_script_spec(spec):
    """True when a config.json server entry describes script tools, not MCP."""
    if not isinstance(spec, dict):
        return False
    if str(spec.get("type") or "").lower() in ("script", "shell", "commands"):
        return True
    # No explicit type but it declares tools and no launch command -> script.
    return bool(spec.get("tools")) and not spec.get("command")
