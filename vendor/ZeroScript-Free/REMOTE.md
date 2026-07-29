# Running the bridge remotely (Railway, a VPS, a container)

By default the bridge binds `127.0.0.1` and has no authentication, because it
**executes commands on the machine it runs on**. This document covers running it
somewhere else — and the safety rules that come with that.

> **Read this first.** A remote bridge is a command-execution service on the
> public internet. Anyone with the token can run every tool you configured. Do
> not expose one unless you understand that, and never point it at a folder
> containing anything you would mind losing or leaking.

## Does this actually help?

Often **no**. Two things it does *not* solve:

- **It does not remove the need for a local machine for Roblox.** Roblox Studio
  runs on your PC; a cloud bridge cannot reach it.
- **It does not let a phone-less setup work.** The browser extension still has
  to run in a browser somewhere.

It *is* useful when you want the tools themselves to run on a server — a shared
workspace, a long-running box, tools that need resources your phone lacks.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `ZS_BRIDGE_HOST` | `127.0.0.1` | Bind address. Use `0.0.0.0` to serve remotely. |
| `ZS_BRIDGE_TOKEN` | *(none)* | Shared secret. **Required** whenever the host is not loopback. Minimum 16 characters. |
| `ZS_BRIDGE_PORT` | `17613` | Port. Falls back to `$PORT` (Railway/PaaS) when unset. |
| `ZS_WORKSPACE` | `~/zs` | Folder the script tools operate in. |

Two guards are enforced at startup, and both are hard failures rather than
warnings:

- Binding off-loopback **without** a token refuses to start.
- A token shorter than 16 characters refuses to start.

## Deploying to Railway

The repo ships `railway.json` and `requirements.txt`, so a deploy needs no extra
build config.

1. Create the project and point it at this folder.
2. Generate a token:
   ```bash
   python -c "import secrets;print(secrets.token_urlsafe(32))"
   ```
3. In Railway → **Variables**, set:
   - `ZS_BRIDGE_HOST` = `0.0.0.0`
   - `ZS_BRIDGE_TOKEN` = the token from step 2
   - `ZS_WORKSPACE` = `/app/workspace` (optional)

   Railway injects `$PORT` itself — do not set `ZS_BRIDGE_PORT`.
4. Deploy. The logs should show:
   ```
   REMOTE MODE: listening on 0.0.0.0 with token authentication required.
   ready N tools available - ... connected
   ```

Keep the token in Railway's variables. Never commit it, and never paste it into
a chat — anyone holding it can run your tools.

## Pointing the extension at it

Open the ZeroScript popup → **🔌 Bridge endpoint**:

- **URL** — `wss://your-app.up.railway.app` (Railway terminates TLS, so use
  `wss://`, not `ws://`).
- **Token** — the same token.

Save & reconnect. The token is stored in `chrome.storage.local` and sent as
`?token=…`; the bridge also accepts `Authorization: Bearer <token>`.

The extension only ships blanket permission for `127.0.0.1`. A remote host is an
*optional* permission your browser will ask you to grant, so installing
ZeroScript never implies access to arbitrary servers.

## Use TLS

`ws://` to a remote host sends the token — and every command and result — in
clear text. Always use `wss://`. Railway gives you HTTPS/WSS automatically; on
your own VPS, put it behind a TLS reverse proxy (Caddy, nginx). The popup warns
when you enter a non-local `ws://` URL.

## Reducing the blast radius

- Trim `config.json` to the fewest tools you need; delete `delete_file` and
  `write_file` if reading is enough.
- Keep `ZS_WORKSPACE` pointed at a dedicated, disposable folder.
- Rotate the token by changing the variable and redeploying; old clients stop
  working immediately.
- Prefer keeping the bridge local. Remote is the exception, not the default.

## Tests

```bash
python3 test_remote_auth.py
```

Ten assertions covering both startup guards, rejection of missing and wrong
tokens, a correct token running a real tool, `$PORT` handling, and that the
loopback default still needs no token.
