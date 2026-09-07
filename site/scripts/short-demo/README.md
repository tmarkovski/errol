# Short demo source

The silent, illustrative film runs for 10.5 seconds at 1280 × 800 and 30 fps.
It uses simplified chat windows and yellow dots with tapered trails. Each dot
dissolves into its destination as the receiving prompt lights up.

To regenerate the checked-in MP4 and poster on macOS, install ffmpeg and run
this command from `site/`:

```sh
zsh scripts/short-demo/build.sh
```

The script uses the macOS Swift compiler and AppKit; it has no dependency on
the Errol app. Frames and compiler output go into a new temporary directory,
printed at the end. The resulting video and poster replace the files in
`public/demos/`. H.264, yuv420p, and fast start allow browser playback without
additional runtime libraries. The site build uses the checked-in assets and
does not need Swift or ffmpeg.

| Time        | Action                                                                     |
| ----------- | -------------------------------------------------------------------------- |
| 0–2.2 s     | The user's prompt travels from Errol into ChatGPT.                         |
| 2.2–5.0 s   | ChatGPT replies and a dot carries its text into Claude.                    |
| 5.2–6.35 s  | A steering note appears in Errol.                                          |
| 6.35–8.55 s | Two dots carry Claude's reply and the steering note into ChatGPT together. |
| 8.55–10.5 s | ChatGPT responds to the new direction and the film holds on the result.    |

`render.swift` contains the layout, dialogue, paths, and timeline. Its `--stills`
option renders representative frames only. The poster is the two-dot steering
frame. Playback runs once on first visibility, unless reduced motion is enabled;
native video controls provide play, pause, seeking, replay, and fullscreen.
