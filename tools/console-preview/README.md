# Native console preview

Run `tools/console-preview/render /tmp/errol-preview` from the repository to compile and render the production views with `PerchPreviewEngine`. It does not rebuild the installed app, use Accessibility, or send messages to either participant. The build requires the same macOS/Xcode generation as the app.

Add `--dark` for dark appearance, and `-appTheme warm-stone` (any theme's identifier) for another theme; the theme is read from the arguments, not saved. Numeric prefixes select scenes, for example:

```sh
tools/console-preview/render /tmp/errol-preview 03 08 09 10 14 15 16 17
```

The scenes cover composition, closed apps, Code sessions, long prompts, running, steering, queued notes, focus recovery, completion, pending pauses, held windows, interrupted delivery, long destination titles, the endings (18: a turn limit with its stepper, and a run that only Stop ends), and Settings (19). State 03 also renders the 600-point layout. States 01, 03, 04, 08, and 15 render a side's details where the app puts them: under the console, with the arrow on the side's icon. Each scene stands in the Xcode canvases' own scene (`PerchPreviewScene`): the capsule wears the theme's window color, as the panel does, and only the windows' shadows are stand-ins. Hover can't be shown, because SwiftUI reads the real pointer. The capture also draws faint ticks at the ends of outlined capsules, as it does for any SwiftUI capsule stroke.

`canvas` renders every state the Xcode canvases show (`PerchPreviewState` in `app/Errol/Errol/Perch/PerchPreviews.swift`), numbered in the canvases' order; `canvas-05` renders one. Only named arguments render them:

```sh
tools/console-preview/render /tmp/errol-preview canvas
tools/console-preview/render /tmp/errol-preview --dark canvas-05 canvas-18
```

Assertions in states 08, 09, and 14 exercise the production controller: a pending pause cannot show a window, a granted hold and note survive Show window, Resume cannot release that hold until the action completes, and both relay-operation gates stay blocked. These are simulated interaction checks, not live copy/send or VoiceOver tests.

The renderer stores its executable and module cache in `/private/tmp/errol-console-preview`. Override this with `ERROL_PREVIEW_BUILD` when needed.
