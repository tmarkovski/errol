// errol-relay: the MCP relay spike's one binary. See README.md.

import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

let usage = """
    errol-relay: the MCP relay spike (see README.md)

      errol-relay mcp        stdio MCP server; the apps start it from the plugin
      errol-relay broker     Errol's stand-in; run it in a terminal and leave it open
      errol-relay new [--topic TEXT] [--first chatgpt|claude] [--turns N] [--hold SECONDS]
                      [--open chatgpt|claude|both] [--chatgpt codex|work|chat] [--claude code|cowork|chat]
      errol-relay note CODE [--to chatgpt|claude|both] TEXT
      errol-relay stop CODE
      errol-relay status
      errol-relay probe [--open chatgpt|claude|both] [--chatgpt MODE] [--claude MODE]
                             print or pre-fill the timing-probe kickoff
      errol-relay selftest   run a broker and two MCP servers against each other
    """

let arguments = Array(CommandLine.arguments.dropFirst())
let config = RelayConfig.fromEnvironment()
switch arguments.first ?? "help" {
case "mcp":
    MCPServer(config: config).run()
case "broker":
    Broker(config: config).serveForever()
case "new", "note", "stop", "status", "probe":
    Control.run(arguments[0], Array(arguments.dropFirst()), config: config)
case "selftest":
    exit(SelfTest.run() ? 0 : 1)
case "help", "-h", "--help":
    print(usage)
default:
    print(usage)
    exit(2)
}
