# Release changes

## V3.5.0

- Smart Selection prefers a single complete control even when its movement is layout-managed. Quick Edit and Select Through let you inspect the individual layer, return to the whole control, or deliberately select its containing bar.
- Rebuilt the toolbar, contextual inspector, and layer browsing around a pinned subset of genuine Lucide icons, native controls, shared visual states, and readable action labels. The standalone release bundles the icon shapes.
- Added a composite-ability practice chapter and regression workflows for free and layout-managed buttons, scope navigation, and restoration. Existing saved profiles and group definitions use the same format.

## V3.4.0

- Unified the editor, onboarding, and notifications with shared surface, type, color, and touch-target tokens. The toolbar emphasizes Save when there are edits, Tools reopens the last workspace, and Quick Edit keeps secondary actions in context. Layers, Groups, and Profiles use quieter rows and contextual management actions.
- Pinch accepts two fingers near the selection, responds to both inward and outward movement, and completes one history action when either finger lifts. Individual and group edits share the same minimum-size rules.
- Relative opacity uses authored appearance while a scope owns a surface. Live, restored, and recreated elements use the same precedence rules. Overlapping CanvasGroup scopes can resolve to supported individual surfaces so one scope does not fade the same surface twice.
- Reset All cancels active transforms, restores eligible controls, and clears selection, guides, handles, and temporary modes. Partial resets report retained protected edits. Undo restores geometry and appearance with the selection clear.
- Improved backup recovery after interrupted saves, preserved the preceding backup on unchanged saves, and blocked stale sessions from overwriting newer checkpoints.

## V3.3.0

- Quick Edit groups Move, Size, Rotate, and Opacity. Direct rotation uses the selection center and supports orbital rotation for compatible groups.
- Opacity fades supported images, text, strokes, backgrounds, and eligible contents relative to their original appearance. Prior BackgroundTransparency saves retain their meaning.
- Panel grips move editor surfaces without editing the HUD. Reset Editor Layout restores the default positions.
- Reset All Changes restores original HUD properties in one undoable action with a device- and orientation-scoped save.
- Quick Start and a chapter-based Guided Tour share isolated practice controls. Help includes a categorized, searchable button reference.

## V3.2.0

- Smart Layers adds friendly names, hierarchy, Select Through, and place-scoped Ignore and Lock rules.
- Quick Group, related-layer selection, and Edit Within Group keep groups independent of the game's GUI hierarchy.
- Per-operation compatibility exposes supported resizing for simple lists and a container route for layout-managed controls.
- The first-run tutorial uses isolated practice controls. Help can replay it at any time.
- Quick Edit, Layers, Settings, and notifications back up touch actions with inline guidance and safe-area placement.
- Existing V3 HUD profiles still load. Editor rules and tutorial progress use a separate local document.
