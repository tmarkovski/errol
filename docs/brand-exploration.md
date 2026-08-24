# Brand exploration

The project began life as **BotBridge**, a working title. This document records the naming exploration that led to **Errol**, so the candidates aren't lost if the name ever needs revisiting. Domain availability was checked via whois/RDAP on 2026-08-24 and will drift over time.

## Chosen: Errol

The Weasley family's elderly owl: not the fastest bird, occasionally crashes into a closed window, but the message always gets delivered. The fit is uncomfortably good, because of what happened on the very first live run.

**The founding incident (2026-08-23).** On the first test, the relay was supposed to type its seed prompt — "Hi! You're talking to another AI assistant through an automated relay between your two desktop apps..." — into the ChatGPT composer. macOS cooperative activation silently ignored the activation call (`NSRunningApplication.activate` returned true and did nothing), and since synthesized keystrokes always go to whatever window is frontmost, the seed was typed into the frontmost terminal instead. That terminal was the Claude Code session that was *building the tool*. The relay's first-ever delivery crashed into the wrong window: it introduced itself to its own author, who received the message mid-development as if the user had typed it. An owl bound for the Burrow, arriving beak-first through the developer's own window.

The incident produced the verified-activation safeguard (never type a keystroke until the target app is confirmed frontmost), and the name was retroactively inevitable.

- `errol.chat` — **registered 2026-08-24**; the project's home (and the TLD suits the product)
- `errol.dev`, `errol.ai` — taken

## Round 1: concept names

Names built on the idea of a go-between for two powers.

| Name | Story | Notes |
|---|---|---|
| Séance | Two disembodied intelligences speak through a medium; the AX-driven cursor is the planchette, the transcript is automatic writing | Strongest concept of the round; carried into round 2 |
| Hotline | The Moscow–Washington hotline: a deliberately slow, text-only channel between rival powers whose first message was a connectivity test ping | Great lore parallel; name fairly common (Hotline Miami, 90s Mac app) |
| Switchboard | The human operator physically patching two lines together — exactly the job this automates | Concrete but less playful |
| Parley | Truce-talk between two parties; short and verb-able | Sits near the ParlAI research framework |
| Détente | Rival powers easing tensions through an intermediary | Considered, not shortlisted |

## Round 2: startup-style respellings

Grindr/Tumblr-style spellings of the round-1 favorites, chosen for domain availability.

| Name | Domains available | Domains taken | Notes |
|---|---|---|---|
| Seancr | seancr.com, seancr.ai | | Reads as "séancer" — the medium conducting the sitting |
| Seyance | seyance.com, seyance.ai | | Gentlest respelling, pronunciation stays obvious |
| Sayance | sayance.ai | sayance.com | Nicest pun (the agents "say" things through the medium) |
| Parleyr | parleyr.com | parlay.com, parlyr.com, parley.ai, parlai.com | Invites misreading ("par-lair") |

## Round 3: pet names (winner's round)

Animals whose job was carrying messages between two parties.

| Name | Story | Domains available | Domains taken | Outcome |
|---|---|---|---|---|
| **Errol** | Clumsy owl, always delivers; matches the tool's origin-story bug | errol.chat | errol.dev, errol.ai | **Chosen** |
| Pigeon | The carrier pigeon; RFC 1149 "IP over Avian Carriers" — this project is RFC 1149 for LLMs | | pigeonpost.com, pidgn.com | Rejected by taste |
| Balto | Sled dog of the 1925 serum run — an actual relay of couriers between stations | balto.dev, balto.chat | balto.ai | Runner-up |
| Togo | Underdog of the same serum run; ran the longest leg, got the least credit | togo.dev | togo.ai | Name collides with the country |
| Myna | The talking bird that repeats what it hears, verbatim, to whoever's in the room | mynah.chat | mynah.dev, myna.ai, mynah.ai | Runner-up |
| Ferret | Labs (Fermilab included) once used ferrets to pull cables through conduits between two points | | ferret.ai | Dropped mid-round; Apple's Ferret model also collides |
