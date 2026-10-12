# Black Violet Islands — Panel Colorizer 8.0.0

Custom appearance preset based on the user's exported settings, checked against upstream 8.0.0 configuration code.
Black blocks, pale text, muted violet borders, violet hover/expanded highlights.
Blur, shadows and continuous color animation are disabled. No RAM usage measurement has been made.

## Install

Save your current appearance as `Before-BlackViolet` in Panel Colorizer's Presets tab first.
Download `BlackViolet-Islands/settings.json` into:

```text
~/.config/panel-colorizer/presets/BlackViolet-Islands/settings.json
```

Use Refresh presets, find BlackViolet-Islands, click Load, enable Panel Colorizer, then Apply.
Preview image is intentionally omitted: live rendering has not been verified.

## Group into islands

Islands and property animation settings are excluded from presets by Panel Colorizer 8.0.0; configure these in the UI.
In Widget Islands enable islands, choose Plasma Panel Spacer (`org.kde.plasma.panelspacer`) as separator and leave 'Require two separators per island' OFF. Keep separator backgrounds excluded.
Use the existing panel spacers to divide your layout:

```text
launcher + applications | flexible spacer | clock | flexible spacer | system tray + other controls
```

The preset does not add/remove/reorder widgets or change panel position, height or visibility.
If the clock is currently part of the tray, it must be separated manually to form its own island.
For smoother effects, enable Animate property changes with duration around 160 ms if available in the settings. This is optional; continuous color animation remains OFF.
Panel height of 36 px is a suggested manual setting if blocks/text feel cramped, not enforced by the preset.

## Rollback

Load Before-BlackViolet or disable Panel Colorizer to remove its appearance effects.
Islands, spacers and animation toggles changed manually must be returned manually.
Keep a backup of ~/.config/plasma-org.kde.plasma.desktop-appletsrc before rearranging widgets; do not replace that file while Plasma is running.

## Validation

JSON parsing and preserved panel-control settings checked. Color sourceType=0 confirmed as custom color in upstream.
Live visual rendering and RAM/CPU consumption must be checked on the user's KDE machine.
