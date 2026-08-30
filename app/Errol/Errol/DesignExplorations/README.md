# Design Explorations

Throwaway visual studies that shaped the real panel skins. Nothing in here
is used by the app at runtime — each file is a gallery of SwiftUI previews
kept for reference, not code to maintain.

- `DesignMockups.swift` — the first four directions (wireframe instrument,
  studio chassis, night signal, quiet frame card), plus the shared
  `MockRun`/`MockPhase` state the other studies render from.
- `DesignMockupsTake2.swift` — the second round: field station, single
  line, and matinee concepts, each with a full and a shrunk variant.
- `DesignMockupsTake3.swift` — the Liquid Glass console and companion
  pane that became `GlassPanelView`.
- `ControlPanelDesignLab.swift` — hardware-flavored control panel
  concepts (dispatch desk, tape loop, patch bay).

The shipped skins live one level up: `WireframePanelView.swift` grew out
of DesignMockups' Option A, and `GlassPanelView.swift` out of Take 3.
