# Native console preview

Run `tools/console-preview/render /tmp/errol-preview` from the repository to compile and render the production views with `PerchPreviewEngine`. It does not rebuild the installed app, use Accessibility, or send messages to either participant. The build requires the same macOS/Xcode generation as the app.

Add `--dark` for dark appearance. Numeric prefixes select scenes, for example:

```sh
tools/console-preview/render /tmp/errol-preview 03 08 09 10 14 15 16 17
```

The scenes cover composition, closed apps, Code sessions, long prompts, running, steering, queued notes, focus recovery, completion, pending pauses, held windows, interrupted delivery, long destination titles, and the endings (18: a turn limit with its stepper, and a run that only Stop ends). State 03 also renders the 600-point layout. States 01, 03, 04, 08, and 15 render a side's details where the app puts them: under the console, with the arrow on the side's icon. Liquid Glass uses a flat stand-in for offscreen rendering, and so does the details panel's window shadow. Hover can't be shown, because SwiftUI reads the real pointer. The capture also draws faint ticks at the ends of outlined capsules, as it does for any SwiftUI capsule stroke.

Assertions in states 08, 09, and 14 exercise the production controller: a pending pause cannot show a window, a granted hold and note survive Show window, Resume cannot release that hold until the action completes, and both relay-operation gates stay blocked. These are simulated interaction checks, not live copy/send or VoiceOver tests.

The renderer stores its executable and module cache in `/private/tmp/errol-console-preview`. Override this with `ERROL_PREVIEW_BUILD` when needed.
