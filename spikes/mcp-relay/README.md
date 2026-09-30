# MCP relay spike

This spike tests whether Errol can carry a conversation through tool calls instead of copying and pasting between chat windows. Each app loads a small stdio MCP server, `errol-relay mcp`, from a plugin. The server passes every tool call to a broker over a Unix socket, and the broker stands in for Errol.

The broker holds one assistant's call open while the other one works. The tool call `errol_send(message)` returns only when the other side has answered, so each assistant spends the whole exchange inside one long turn. Neither app needs focus or the clipboard, and nobody has to watch it.

It's a standalone Swift package and not part of the app. It shares no sources with the app or with the root package, and building it never touches Errol.app. It was built and run on 2026-09-30:
- **ChatGPT:** the bundled Codex (`codex-mcp-client 0.159.2`, model `gpt-6.1-sol`).
- **Claude:** the desktop app's Code tab (Claude Code 2.1.284, Opus 5.5).

## Verdict

- **The idea works where the app runs its agent loop on the Mac.** That covers ChatGPT's Codex and Work modes and Claude's Code tab, all tested, and Claude's Cowork according to Anthropic's docs. A plugin's local server can't be used in ChatGPT's Chat mode, and Claude's Chat mode ignores servers that come from plugins.
- **A relay call can wait for minutes.** Calls of 90, 150 and 330 seconds all came back normally in both apps, in the same turn. ChatGPT honours the plugin's own `tool_timeout_sec`, and the Code tab doesn't move long calls to the background.
- **The models can do it.** A 9-message conversation ran as one turn on each side, in 8.5 minutes. Both followed the protocol, used `done` sensibly, acted on a steering note sent mid-session, and wrote the user a summary at the end.
- **It removes what makes the Accessibility relay fragile.** Errol gets the exact Markdown each assistant wrote. It needs no focus and no clipboard. Nothing has to infer that a reply has finished, because the next call says so.
- **What it can't do alone is wake an agent that has stopped calling.** The server can only answer calls. When an agent ends its turn, Errol would still need its composer write to bring it back.

## Where it works

| Mode | Local stdio server | How to register it | Evidence |
|---|---|---|---|
| ChatGPT Codex | yes | plugin, or `[mcp_servers]` in `~/.codex/config.toml` (`codex mcp add`) | tested |
| ChatGPT Work | yes | the same | tested |
| ChatGPT Chat | no | not possible; only an HTTPS server that OpenAI's servers can reach | tested |
| Claude Code | yes | plugin, or `claude mcp add` or `.mcp.json` | tested |
| Claude Cowork | yes, in local sessions | plugin | Anthropic's docs |
| Claude Chat | yes, but not from a plugin | `claude_desktop_config.json` or a `.mcpb` Desktop Extension | Anthropic's docs |

**The Chat modes can use remote HTTP servers, not local ones.** A Chat conversation runs in the vendor's cloud, which calls a connector's URL over the internet. A server pointed at `localhost` wouldn't work either, because the call comes from the vendor's servers.

**ChatGPT Chat has no local route at all.** Getting ChatGPT's Chat mode in would need a public endpoint, either a hosted relay or a tunnel to the Mac. That ends Errol's "no account, no server" promise.

**Claude Chat is the exception.** The Claude app runs local servers from its own config and passes tool calls between them and Chat. The same GitHub reports describe two limits we haven't tested: a tool call is cut off after about 4 minutes, and a turn stops at about 20 tool calls with a Continue button.

**Direct registration works as well as the plugin wherever a local server runs.** The plugin is packaging: one folder for both apps, installed and removed through each app's own plugin screens. Direct registration is the only route into Claude Chat.

## What we measured

### The timing probe

Each app called `errol_probe_wait` with 90, 150 and 330 seconds, one after another.

| Wait | ChatGPT (Codex mode) | Claude (Code tab) |
|---|---|---|
| 90 s | returned normally | returned normally |
| 150 s | returned normally | returned normally, same turn, not backgrounded |
| 330 s | returned normally, past Codex's 300 s built-in default | returned normally, same turn |

**Neither model saw a status message from its app while it waited.** Codex prefixes every MCP result with `Wall time: … seconds`.

**The Code tab doesn't move long calls to the background.** The interactive Claude Code CLI moves MCP calls longer than 120 s to the background (`CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS`), but the Code tab didn't. Most likely it runs as a non-interactive SDK session, where the binary skips auto-backgrounding unless `CLAUDE_AUTO_BACKGROUND_TASKS` is set.

### The conversation: session S-VP7S

The topic was undo and redo in a collaborative editor. ChatGPT opened, the limit was 10 messages, and calls were held for up to 15 minutes.

- **Each side stayed in one turn.** Claude's turn was `errol_join`, then four `errol_send` calls. ChatGPT's was `errol_join`, then five `errol_send` calls. Each call returned the other side's next message.
- **Replies took about a minute each.** Measured from each message to the one that answered it, the times ranged from 15 s to 115 s, and most were under a minute. The session took 8.5 minutes and carried about 23,800 characters.
- **It ended by agreement after 9 of the 10 messages.** No hold ran out. There were no retries, re-deliveries, cancellations or out-of-turn sends.
- **Both followed the protocol throughout.** Every reply went into `errol_send`.
  - Claude wrote no visible text until the end.
  - ChatGPT wrote short progress lines for the user between calls. It also opened the Yjs `UndoManager` docs and source with its own web tool, so each assistant brought its own tools to the exchange.
  - Both wrote a summary for the user in their own app when the session ended.
- **`done` worked as intended.**
  - ChatGPT marked message 5 done. Claude kept going, because the user's note had just arrived with that message asking for counter-examples.
  - ChatGPT picked the thread back up with `done: false` once the note reached it.
  - Claude closed with message 8 and ChatGPT with message 9.
- **Both acted on the steering note.** It asked each side for an edit sequence that breaks the other's design. Claude's case of an oversized deletion evicting the newest undo entry changed the final recommendation.
- **No approval prompt showed on the ChatGPT side,** which fits the plugin's `default_tools_approval_mode: "approve"`. The Claude session ran in auto mode (`permissionMode: auto` in its transcript), so it doesn't show whether a Code tab user in the default mode would be asked.

### ChatGPT's Work mode

It uses the plugin, even though OpenAI's docs group Work with Chat as remote-only.
- **Opening a Work thread launched the plugin's server.** ChatGPT started it in the thread's own folder, `~/Documents/Codex/2026-09-30/<slug>`, and listed its tools.
- **The model answered from the plugin's instructions.** Asked whether it could use the plugin, it offered to join given "a ticket like ERR-7F3K", which is our wording.
- **A real call got through.** Its `errol_join` reached the broker and came back; the result was "unknown ticket" only because it tried that example ticket.
- **Work runs on the same harness as Codex mode.** The call's metadata shows `source: codex`, the same model and the same `workspace-write` sandbox, with `workspace_kind: projectless` and no workspaces listed.

So ChatGPT's knowledge-work mode can use the relay, and so can its coding mode.

### ChatGPT's Chat mode

The plugin appears in Chat's @-mention menu, because the app keeps one plugin list across modes. But the model reports no errol tools, even with `@errol-relay` mentioned, and nothing reached the server or the broker.

The model suggested looking for Install or Connect under Settings. That wouldn't help, because a process on the Mac can't be reached from OpenAI's servers. A shipped plugin would look usable in Chat and do nothing there, so Errol would have to say which modes it covers.

### Other observations

- **Codex tells every plugin server who is calling.** Each `tools/call` carries `_meta.x-codex-turn-metadata`:
  - the thread and turn ids
  - the model, the reasoning effort and the sandbox mode
  - for a project thread, the workspace with its git remotes and commit hash

  So Errol could bind a session to a ChatGPT thread without a ticket. The privacy cost is that every plugin server gets this metadata.
- **Claude Code sends only `claudecode/toolUseId`,** so the Claude side still needs a ticket or some other binding.
- **Codex launches the server often.** Opening one Work thread launched it 13 times in about 45 seconds. Only one process per open thread or session stays running, at about 10 MB each. The server has to start cheaply and stay quiet when idle.
- **The two apps negotiate different MCP protocol versions.** Claude Code asks for 2025-11-25 and Codex for 2025-06-18; echoing the client's version works for a tools-only server.
- **Claude Code resolves "local" scope to the enclosing git repo's root.** Run from a folder inside Errol's repo, `claude plugin install --scope local` wrote `errol/.claude/settings.local.json`. That is why `playground/` is a repo of its own.
- **A signed binary copied over in place is killed on launch** (SIGKILL, exit 137). `spike.sh build` copies beside it and renames.

## Design notes for the real thing

- **The protocol is three tools plus a probe.**
  - `errol_join(ticket)` returns the briefing, and either the cue to open or the other side's message.
  - `errol_send(ticket, message, done)` delivers a reply and waits for the answer.
  - `errol_wait(ticket)` keeps waiting after a hold runs out.
  - The broker writes every sentence the assistants read ([`Wording.swift`](Sources/errol-relay/Wording.swift)). The server just passes calls through, so the protocol's voice lives in Errol.
- **Holds stay under each app's limit.** The broker answers "still waiting, call errol_wait" before the hold runs out. It sends a progress notification every 15 s, which Claude Code shows and Codex ignores.
- **The broker is built for apps that drop results.** Codex doesn't cancel a call it times out, so a late result would simply be lost. To cope with that, the broker:
  - lets a newer call from the same side supersede an older one
  - delivers an unanswered message again if the side calls again
  - treats a repeated identical send as a retry
  - hears a cancelled call when the server closes its connection
- **The other side's message is marked off from Errol's words.** Deliveries wrap it in `<message from="…">`. Because it arrives as a tool result, both vendors' models treat it as information, not instructions, unless the user delegates authority. The kickoff therefore frames the other side as a colleague to discuss with, and forbids editing files or running commands at its request.
- **The conversation lives in tool arguments.** Each app shows collapsed tool rows, so Errol's console is where you read the conversation. Each agent writes the user a summary in its own app when the session ends.
- **Waking a dropped agent is Errol's job.** The server can't start a turn. Deep links only pre-fill a new composer:
  - `codex://new?prompt=…&mode=chat|work|codex`
  - `claude://code/new?q=…&folder=…`
  - `claude://claude.ai/new?q=…&surface=chat|cowork`

  Writing into a composer and pressing Send, which Errol already does, is how to start a session or wake an agent that stopped.
- **It fits behind the existing seam.** [`RelayEngine`](../../app/Errol/Errol/Engine/RelayEngine.swift) already separates the controller from the machinery, so an MCP engine could sit next to `LiveRelayEngine`. Steering notes and the delivery gate become queue operations in the broker.

## Open questions and next steps

1. **Work with Cowork,** the non-coding pair. `new --chatgpt work --claude cowork --open both` launches both. Cowork first needs the plugin where it can see it, at user scope or through Cowork's plugin settings.
2. **Claude Chat through `claude_desktop_config.json` or a `.mcpb`.** Run the probe there to see whether the reported 4-minute cutoff and the 20-calls-per-turn Continue apply to local servers. This needs a restart of the Claude app.
3. **The failure paths in real apps:**
   - an agent that ends its turn early, and waking it through its composer
   - Stop pressed in an app mid-call
   - a reply slower than the hold
4. **Approval prompts in Claude's default permission mode.** Can a first-run install pre-allow `mcp__plugin_errol-relay_errol__*` without a plugin, which can't ship allow rules?
5. **Session binding.** Codex's thread ids would let Errol skip tickets on the ChatGPT side, and the Claude side needs its own answer.
6. **Packaging.** One plugin plus a `.mcpb` for Claude Chat, or direct registration through `codex mcp add`, `claude mcp add` and the desktop config.

## Layout

- **`Sources/errol-relay/`** builds the one binary.
  - [`MCPServer.swift`](Sources/errol-relay/MCPServer.swift) is the stdio server. Each tool call becomes one connection to the broker, and every JSON-RPC message in and out lands in `run/logs/mcp-<pid>.jsonl`.
  - [`Broker.swift`](Sources/errol-relay/Broker.swift) runs the sessions and logs every call's timing to `run/logs/broker.jsonl`. It prints the conversation to its terminal and keeps it in `run/logs/transcripts/<code>.md`.
  - [`Wording.swift`](Sources/errol-relay/Wording.swift) holds everything the assistants read.
  - [`Control.swift`](Sources/errol-relay/Control.swift) has the `new`, `note`, `stop`, `status` and `probe` commands and the deep links.
  - [`SelfTest.swift`](Sources/errol-relay/SelfTest.swift) runs the broker and two server processes through scripted sessions: 29 checks, no apps needed.
- **[`spike.sh`](spike.sh)** builds the binary, writes the plugin with this checkout's absolute paths, and installs or uninstalls it.
- **Generated and ignored:** `bin/`, `run/`, `marketplace/` and `playground/`.

### One plugin, two apps

`./spike.sh plugin` writes `marketplace/`. Each app reads its own manifest from the same plugin folder, and each manifest points at an MCP config written for that app:

- **Claude Code** reads `.claude-plugin/plugin.json`, which points at `claude.mcp.json`. It sets a per-server `timeout` of 3600000 ms.
- **ChatGPT** reads `.codex-plugin/plugin.json`, which points at `codex.mcp.json`. It sets:
  - `tool_timeout_sec: 3600`
  - `default_tools_approval_mode: "approve"`
  - `omit_tools_from: ["code_mode", "deferred"]`, the key OpenAI's own bundled plugins use to keep a tool out of code mode's exec cells. The model then called the tool directly.
- **Both use absolute paths,** because Codex doesn't expand `${CLAUDE_PLUGIN_ROOT}`.

`./spike.sh install` installs the plugin in two places:
- **Claude Code,** for `playground/` only.
- **ChatGPT,** for every Codex and Work thread. It first saves a copy of `~/.codex/config.toml` in `run/`.

`./spike.sh uninstall` removes both.

## Running it

```bash
./spike.sh build
bin/errol-relay selftest
./spike.sh install
./spike.sh broker
```

Then, from another shell:

```bash
bin/errol-relay probe --open both
bin/errol-relay new --turns 10 --open both
bin/errol-relay new --chatgpt work --claude cowork --open both
```

- **`probe`** puts the timing probe into both composers.
- **`new`** creates a session and puts each app's kickoff, with its ticket, into its composer. The links only pre-fill, so you press Send in each app. The Work and Cowork links haven't been tried yet.
- **`note CODE TEXT`** adds a steering note to the next delivery, and **`stop CODE`** ends a session.

## Sources

These came from web research during the spike and weren't all re-checked.

- **Vendor docs:**
  - OpenAI: [Codex and ChatGPT MCP](https://learn.chatgpt.com/docs/extend/mcp) and [plugins](https://developers.openai.com/plugins/build/plugins).
  - Anthropic: [plugin platform support](https://claude.com/docs/plugins/platform-support), [local MCP servers on Claude Desktop](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop), [Cowork architecture](https://support.claude.com/en/articles/14479288-claude-cowork-architecture-overview), [Claude Code MCP](https://code.claude.com/docs/en/mcp).
- **User reports on Claude Desktop's limits:**
  - About 4 minutes per tool call: [anthropics/claude-code#91898](https://github.com/anthropics/claude-code/issues/91898) and [anthropics/claude-code#65643](https://github.com/anthropics/claude-code/issues/65643).
  - About 20 tool calls per turn: [anthropics/claude-code#33969](https://github.com/anthropics/claude-code/issues/33969).
- **Prior art:**
  - [openai/codex-plugin-cc#634](https://github.com/openai/codex-plugin-cc/issues/634): backgrounding made a subagent end its turn.
  - [suneel944/agent-parley#260](https://github.com/suneel944/agent-parley/issues/260): polling, or a human restart for every question.
  - [codex-claude-bridge](https://github.com/abhishekgahlot2/codex-claude-bridge): "nothing can push into an idle Codex".
  - [claude-codex-mcp-bridge](https://github.com/WebisityStudio/claude-codex-mcp-bridge): long-polls for 285 s.
  - [MCP Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail).
