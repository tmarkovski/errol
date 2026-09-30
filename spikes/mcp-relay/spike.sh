#!/bin/zsh
# Setup for the MCP relay spike (see README.md).
#
#   ./spike.sh build       build bin/errol-relay
#   ./spike.sh plugin      write marketplace/ with this checkout's absolute paths
#   ./spike.sh install     install the plugin: Claude Code for the playground/
#                          folder only, ChatGPT's Codex mode for every thread
#   ./spike.sh uninstall   take both installs out again
#   ./spike.sh broker      run the broker in this terminal
#
# One plugin folder serves both apps. Each app reads its own manifest
# (.claude-plugin/plugin.json or .codex-plugin/plugin.json), and each
# manifest points at an MCP config written in that app's dialect: Claude
# Code's per-server timeout is `timeout` in milliseconds, while Codex's is
# `tool_timeout_sec`, and only Codex knows approval modes and code mode.
# Codex doesn't expand ${CLAUDE_PLUGIN_ROOT}, so both use absolute paths.

set -euo pipefail

ROOT=${0:A:h}
BIN=$ROOT/bin/errol-relay
RUN=$ROOT/run
MARKET=$ROOT/marketplace
PLUGIN=$MARKET/plugins/errol-relay
PLAYGROUND=$ROOT/playground
CODEX=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex

build() {
  swift build -c release --package-path "$ROOT"
  mkdir -p "$ROOT/bin"
  # Copy beside it, then rename: a signed binary rewritten in place is
  # killed on launch (SIGKILL, exit 137), and the rename also leaves any
  # server the apps are running on the old file untouched.
  cp "$(swift build -c release --package-path "$ROOT" --show-bin-path)/errol-relay" "$BIN.new"
  mv -f "$BIN.new" "$BIN"
  echo "Built $BIN"
}

plugin() {
  mkdir -p "$MARKET/.claude-plugin" "$MARKET/.agents/plugins" \
    "$PLUGIN/.claude-plugin" "$PLUGIN/.codex-plugin" "$RUN/logs"

  cat > "$MARKET/.claude-plugin/marketplace.json" <<EOF
{
  "name": "errol-spike",
  "owner": { "name": "Errol" },
  "description": "The MCP relay spike, installed from this checkout.",
  "plugins": [
    {
      "name": "errol-relay",
      "source": "./plugins/errol-relay",
      "description": "Relay a conversation between ChatGPT and Claude through Errol."
    }
  ]
}
EOF

  cat > "$MARKET/.agents/plugins/marketplace.json" <<EOF
{
  "name": "errol-spike",
  "interface": { "displayName": "Errol spike" },
  "plugins": [
    {
      "name": "errol-relay",
      "source": { "source": "local", "path": "./plugins/errol-relay" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Developer Tools"
    }
  ]
}
EOF

  for app in claude codex; do
    cat > "$PLUGIN/.$app-plugin/plugin.json" <<EOF
{
  "name": "errol-relay",
  "version": "0.1.0",
  "description": "Relay a conversation between ChatGPT and Claude through Errol (spike).",
  "author": { "name": "Errol" },
  "mcpServers": "./$app.mcp.json"
}
EOF
  done

  cat > "$PLUGIN/claude.mcp.json" <<EOF
{
  "mcpServers": {
    "errol": {
      "command": "$BIN",
      "args": ["mcp"],
      "env": { "ERROL_RELAY_SOCKET": "$RUN/relay.sock", "ERROL_RELAY_LOG_DIR": "$RUN/logs" },
      "timeout": 3600000
    }
  }
}
EOF

  cat > "$PLUGIN/codex.mcp.json" <<EOF
{
  "mcpServers": {
    "errol": {
      "command": "$BIN",
      "args": ["mcp"],
      "env": { "ERROL_RELAY_SOCKET": "$RUN/relay.sock", "ERROL_RELAY_LOG_DIR": "$RUN/logs" },
      "startup_timeout_sec": 20,
      "tool_timeout_sec": 3600,
      "default_tools_approval_mode": "approve",
      "omit_tools_from": ["code_mode", "deferred"]
    }
  }
}
EOF
  echo "Wrote $MARKET"
}

install() {
  plugin
  mkdir -p "$PLAYGROUND"
  # Claude Code: declared and enabled in playground/.claude/settings.local.json,
  # so only Code sessions opened in that folder load the plugin. Claude Code
  # takes the enclosing git repo's root as the project, so the playground is
  # a repo of its own; otherwise the install lands in Errol's .claude/.
  [[ -d "$PLAYGROUND/.git" ]] || git -C "$PLAYGROUND" init -q
  (cd "$PLAYGROUND" && claude plugin marketplace add "$MARKET" --scope local \
    && claude plugin install errol-relay@errol-spike --scope local)
  # Codex has no per-folder scope: this adds the marketplace and the plugin
  # to ~/.codex/config.toml. A copy of the file goes into run/ first.
  cp ~/.codex/config.toml "$RUN/codex-config.before-install.toml"
  "$CODEX" plugin marketplace add "$MARKET"
  "$CODEX" plugin add errol-relay@errol-spike
}

uninstall() {
  (cd "$PLAYGROUND" && claude plugin uninstall errol-relay@errol-spike --scope local) || true
  (cd "$PLAYGROUND" && claude plugin marketplace remove errol-spike) || true
  "$CODEX" plugin remove errol-relay@errol-spike || true
  "$CODEX" plugin marketplace remove errol-spike || true
}

case ${1:-help} in
  build|plugin|install|uninstall) "$1" ;;
  broker) exec "$BIN" broker ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
