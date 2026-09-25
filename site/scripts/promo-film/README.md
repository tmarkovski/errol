# Promo film source

A 23-second promotional film in two formats from one source: **tall**, 1080 × 1920
(9:16) for Reels, TikTok, and Shorts, and **wide**, 1920 × 1080 (16:9) for the
landing page and anywhere else. Both run at 60 fps with a synthesized sound track.

`promo.html` draws every frame as a pure function of time, so a render is
deterministic and any single frame can be inspected. `render.py` drives headless
Chrome to capture the frames, encodes them with ffmpeg, synthesizes the sound
from the same timeline (`sound.py`), and muxes the two.

## Watching and rendering

Open the page in Chrome to watch it play; space pauses, and clicking the bar seeks:

```sh
open "promo.html?format=wide&play"
```

`&t=9.3` in place of `&play` holds a single frame. The page loads Geist from
Google Fonts and the app icons from `../../public/app-icons/`.

Rendering needs [uv](https://docs.astral.sh/uv/) and Google Chrome. `render.py`
declares its Python dependencies inline, so `uv run` installs them on first use;
without Chrome, run `uv run --with playwright playwright install chromium` once
and it falls back to Playwright's Chromium. From this folder:

```sh
uv run render.py build                    # both films, with sound
uv run render.py build --format wide      # one of them
uv run render.py stills 3.3 9.3 --sheet   # single frames and a contact sheet
uv run render.py cues                     # the timeline the sound follows
uv run render.py publish                  # web encodes of both into the site's public/demos/
uv run render.py hold 6.75 0.5            # add half a second at 6.75 s
```

`hold` lengthens the film: every time in the story from that point on moves
later, and `DUR` grows to match. The renderer and the sound read the length from
the page, so nothing else needs changing.

`build` writes into `out/` (ignored by git), in about a minute per format:
`errol-promo-9x16.mp4` and `errol-promo-16x9.mp4` with sound at -14 LUFS, a
`-silent` cut of each for laying in licensed music, and a `-cover` PNG of each.
The MP4s are H.264 High, yuv420p, tagged BT.709, with fast start.

The landing page plays the films from `public/demos/`. After a `build`, `publish`
re-encodes both for the web (CRF 23 and 128 kbps audio, about 4 MB each and
indistinguishable on the page) and saves each one's first frame as a WebP poster,
so playback starts without a jump.

Those four files aren't committed. The site's deploy workflow renders them on a
GitHub runner and keeps them in R2 under a hash of this folder's `promo.html`,
`render.py`, and `sound.py` plus the two app icons the film loads, so a render
happens once per change to the source, and every deploy fetches the films for
the commit it's shipping. `films.sh` does the R2 side:

```sh
./films.sh key      # the hash of the source
./films.sh fetch    # the films for this source, into public/demos/
./films.sh store wide   # upload the wide film and poster in public/demos/ under the hash
```

`store` lets a local render stand in for the runner's: render and publish on
your Mac, commit the source, then store both formats, and CI finds the films
already there.
It needs `npx wrangler login` first, as `fetch` does.

## Editing

Everything a change usually touches is in the `STORY` block at the top of the
script in `promo.html`, and it applies to both formats:

- `BEAT` holds the scene beats: when the pen draws the logo, when the console
  drops, Start relay, Pause, Send note & continue, and the end card's moments.
  Secondary motion is timed as offsets from these, so moving a beat moves what
  hangs off it.
- `HOPS` is the relay, one entry per delivery: which side Errol copies from, when
  the dot leaves and lands, and the reply that streams in afterwards. The pages in
  each chat, the pasted text, the flight paths, the console's status and turn
  lines, and the badges are all derived from it. The first hop carries `TOPIC`;
  each later hop carries the previous reply; a hop with a `note` also carries the
  note typed while paused, and the console's receipt names that hop's turn.
- `HOOK` is the opening, where you relay by hand: each chat's pages, what gets
  pasted, the Copy presses, and the keystrokes on the conveyor.
- `CAPTIONS`, `EYEBROWS`, `TAGLINE`, `END_LINE`, `PILL`, and `CTA` are the copy.
  Captions rise word by word; leave 0.35 s between one caption leaving and the
  next arriving, or the two overlap.
- `CURSOR` moves the pointer between named spots (a chat's Copy button or
  composer, the console's buttons), which each layout resolves to its own
  positions.

`LAYOUTS` places everything per format: the chat windows, the console's three
shapes (setup, running, and paused with a note), the menu bar, the logo scenes,
the end card, and where the glow sits in each scene. `route()` shapes the dot's
flights: in the tall film a hop crosses the console in an S, and in the wide
film it dips through the console in a U.

The sound design reads its cue times from the page (`window.CUES`), so retiming
the picture retimes the sound. Each delivery chimes one step higher, and the
whooshes pan with the dot, so in the wide film ChatGPT sits on the left and
Claude on the right. The music is a chord pad, one chord per scene, synthesized
along with everything else in `sound.py`.

The Errol symbol's two paths are inlined in `I.sym`; keep them in sync with
`docs/brand/errol-symbol.svg`.

## Storyboard

| Time          | Beat                                                                                                                    |
| ------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 0–2.4 s       | "Still copy-pasting between your AIs?" A cursor relays by hand while ⌘C, ⌘V, and ↩ ride a conveyor where Errol will sit. |
| 2.4–5.8 s     | The apps step back. The gold dot draws the symbol and lands as the wordmark's period. "Let ChatGPT and Claude talk it out." holds long enough to read. |
| 5.8–8.5 s     | 01 Topic. The symbol flies into the menu bar and the console drops from it. Both apps check in, the topic is typed and holds for a moment, then Start relay. |
| 8.5–14.7 s    | 02 Relay. "Errol carries every reply," then "No API keys. Just your Mac apps." Copy, a flight through Errol, delivery, and the next reply, each hop quicker. |
| 14.7–18.7 s   | 03 Steer. "Step in whenever you like." Pause, type a note, Send note & continue; the reply and the note land in ChatGPT together, and its answer holds. |
| 18.7–23 s     | The symbol's two bubbles meet, the dot lands as the period, then "Let your AIs talk.", Free · Open source · For Mac, and errol.chat. |

In the tall film, captions and the end card stay clear of the top 200 px and the
bottom 380 px, where the social apps overlay their own controls.
