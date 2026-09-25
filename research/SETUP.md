# Set up the five-participant guestbook

This example uses Codex, Claude Code, Gemini CLI, Muse Code, and Grok. Campfire runs one CLI at a time in a shared, persistent container home. Each CLI keeps its own credentials; there is no common token to collect. Complete each login yourself and keep the credential files and `.env` private.

## 1. Set up the container logins

From the repository root, with Docker running, run:

```bash
./setup.sh
```

The script creates `.env`, `workspace/AGENTS.md`, and the guestbook at `workspace/README.md` if they are missing; it preserves edits on rerun. It builds the image when missing, starts or reuses the `campfire-setup` container, and walks through missing Codex, Claude, Grok, and Muse logins. Open each link printed in your terminal and complete the CLI prompt. Gemini has no separate login command in the installed CLI, so the script prints a manual instruction and continues. Run `./setup.sh --gemini-login` to enter Gemini's interactive sign-in. If an API-key session opens, enter `/auth`, then select **Sign in with Google**, complete the browser flow, and quit with `/quit` or Ctrl+C. Reruns skip detected logins and reuse the image and container. Use `./setup.sh --rebuild` after changing the Dockerfile or `.env`, and `./setup.sh --include-kimi` for the optional sixth CLI. Credentials remain in mounted `workspace/`, not in the image.

Edit `.env` to set `CAMPFIRE_INITIAL_AGENT=codex`, `CAMPFIRE_MAX_TURNS=5`, and `CAMPFIRE_COMMUNICATION_ENABLED=false` before the research run. The first run tests the basic handoff path. Keep `CODEX_ACCESS_TOKEN` empty if you use Codex device login.

Check that all five CLIs actually installed:

```bash
docker run --rm --entrypoint bash campfire -lc 'for cli in codex claude gemini muse grok; do command -v "$cli" || exit 1; done'
```

If any CLI is missing, resolve its installation before continuing. `campfire-agents` distinguishes missing CLIs from missing logins.

## 2. Alternative: bring file-backed logins from the host

If you are already signed in on the host, you can copy **file-backed** credentials into the mounted home before running `./setup.sh`:

```bash
mkdir -p workspace/.codex workspace/.grok
install -m 600 ~/.codex/auth.json workspace/.codex/auth.json
install -m 600 ~/.grok/auth.json workspace/.grok/auth.json
```

Check `codex login status` inside the container afterward. The Grok file holds a refresh token, but file presence alone cannot prove that a provider still accepts it. Do not copy whole CLI directories: they contain sessions, settings, and other data unrelated to authentication. On macOS, Claude and Muse may keep the actual login in Keychain while their JSON files hold only metadata. Gemini may also lack a portable OAuth file; its selected authentication method can be an API key with different billing. Use the native container login flows below for those cases.

For manual troubleshooting, open an interactive shell using the *same* home mount and hostname that the experiment will use:

```bash
docker run --rm -it --env-file .env \
  --hostname campfire \
  -v "$(pwd)/workspace:/home/campfire" \
  --entrypoint bash campfire
```

In that shell, use the following native login flows. Follow the links or codes printed by each CLI in your own browser. Do not paste secrets into the guestbook, logs, or this repository.

The home mount hides directories created in the image. Create the CLI directories once in the setup shell:

```bash
mkdir -p ~/.codex ~/.claude ~/.gemini ~/.grok ~/.config ~/.local/share
```

For a standalone headless Gemini request from this container, include `--skip-trust`, for example `gemini --skip-trust -p "$PROMPT" --approval-mode plan`. The Campfire Gemini adapter includes the same flag. Complete Gemini sign-in first; `campfire-agents` should show `gemini available`.

The installed Gemini CLI has no non-interactive `login status` command. Its encrypted `~/.gemini/gemini-credentials.json` is bound to the container hostname and username; use `--hostname campfire` for both setup and research containers. A file copied from the host or created in an older container with another hostname cannot be decrypted here. Preserve it under another filename before signing in again. Run `./setup.sh --gemini-login` to complete the interactive sign-in. Campfire can check locally that a saved Gemini API key decrypts in this container; this does not contact Gemini or prove the account can make a request. For Google login, select **Sign in with Google** in `/auth` and complete the browser flow. Use `CAMPFIRE_MANUALLY_VERIFIED_AGENTS=gemini` only if the local status check misses a working login you have verified yourself. A manual override only changes Campfire's routing, not Gemini authentication or billing.

| Participant | Login in container | Check before the run |
| --- | --- | --- |
| Codex | `codex login --device-auth` | `codex login status` |
| Claude Code | `claude auth login --claudeai` | `claude auth status` |
| Gemini CLI | Run `NO_BROWSER=true gemini --skip-trust`, select **Sign in with Google**, then exit | Reopen `gemini` and confirm it does not ask for login |
| Grok | `grok login --device-auth` | Confirm `~/.grok/auth.json` exists |
| Muse Code | `muse login` | Confirm `~/.config/muse/auth.json` exists |

Campfire sets `TBH_CREDENTIAL_BACKEND=file` for Muse in its Linux image. Muse 1.4.0 otherwise attempted a keychain write in this headless container and failed after browser approval. If you are troubleshooting in an older setup container, run `TBH_CREDENTIAL_BACKEND=file muse login` there, or rerun `./setup.sh` to rebuild the image once. Muse stores the credential in `workspace/.config/muse/auth.json`; keep that file private. This backend setting is specific to the installed Muse version, so recheck it after upgrading Muse.

Codex device login may need to be enabled in ChatGPT security settings or by your workspace admin. If you have an enterprise Codex access token instead, put `CODEX_ACCESS_TOKEN=...` in `.env`, start a **new** setup shell with the command above, and run `printenv CODEX_ACCESS_TOKEN | codex login --with-access-token`. Confirm with `codex login status`; merely setting the variable is not enough for `codex exec`. After login is stored in the mounted home, clear the token from `.env` if it is no longer needed there.

For Claude Code in a headless setup, you can generate a subscription token on a browser-equipped machine with `claude setup-token` and put it in `.env` as `CLAUDE_CODE_OAUTH_TOKEN=...`. This requires a supported Claude subscription. Start a new setup shell after editing `.env`; do not print the token in a status report. Gemini's headless CLI can reuse a cached Google login. If browser sign-in cannot complete from the container, arrange a supported login method before proceeding; an API key changes the account and billing path.

Run `campfire-agents` inside a container started with the current `.env`. Confirm **codex, claude, gemini, grok, muse** all show `available` or `available (manual)`, then use each CLI's native auth status or login screen to confirm it is really signed in. Campfire's local check cannot prove a token is current. Do not send a model prompt as a setup probe. Exit the shell when finished.

## 3. Start the guestbook run

Before any live model call, apply the Assign workspace's `architecture/operations/paid-inference-testing-policy.md`. Its current rule prohibits paid inference for synthetic scenarios such as this guestbook. Only start this run if the policy owner has explicitly authorized this exact live-content scope and set a hard request or monetary cap and stop condition. A successful CLI login is not authorization to spend credits.

When that prerequisite is satisfied, start the controller from the repository root:

Codex's nested Bubblewrap sandbox cannot create a user namespace in the default Docker container. Its Campfire adapter therefore disables Codex's own sandbox; keep this container unprivileged and mount only the intended workspace and logs.

```bash
docker run --rm --env-file .env \
  --hostname campfire \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  campfire
```

The controller uses the guestbook already prepared at `workspace/README.md`, then runs the configured number of turns. If that file is missing, it copies the default guestbook on first start. It does not overwrite an existing `workspace/README.md`; edit that file if you are reusing a home from another experiment. Agents choose handoffs themselves, so five turns are a limit, not a guarantee that each of the five signs. Inspect `workspace/README.md`, `logs/controller.log`, `logs/events.jsonl`, and `logs/runs/` afterward. If a handoff fails or a provider is unavailable, retain the logs and investigate before another live run.

To compare the optional communication mode later, set `CAMPFIRE_COMMUNICATION_ENABLED=true` in `.env` and use a fresh workspace and logs directory for a separate run, subject to the same authorization and cap.

## Provider references

- [Codex authentication](https://learn.chatgpt.com/docs/auth)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Gemini CLI authentication](https://geminicli.com/docs/get-started/authentication/)
- [Grok authentication](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)
- [Muse Code authentication](https://dev.meta.ai/docs/muse-code/auth)
