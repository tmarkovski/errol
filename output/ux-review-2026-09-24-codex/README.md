# Earlier layout alternative

This preserves the interactive illustration originally shown in the review conversation. It is a schematic HTML alternative using sample content, not a screenshot of the native app. Its controls simulate a relay locally.

- [Open the standalone copy](earlier-layout.html).
- [Editable fragment](earlier-layout.fragment.html).

After reviewing the app's actual stage-by-stage renders and Claude's proposal, the preferred direction is the refined capsule described in the [peer review](../ux-review-2026-09-24-codex-peer-review.md). The reviewed native proposal images are [preserved alongside Claude's assessment](../ux-review-2026-09-24-claude/).

The standalone page preserves the default arrangement and local session controls. The fragment's optional design controls are available when embedded in a host supplying the Tweak helper.

The standalone file was exported with the visualize skill's `scripts/render.py`, using `uv run --no-project --offline python`. Only `window.openai.widgetState` and `window.openai.setWidgetState` are used, with guards for a host that does not provide them.
