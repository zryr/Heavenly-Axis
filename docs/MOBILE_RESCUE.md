# Heavenly Axis V3 mobile rescue

The Android landscape flow is **open → tap a HUD control → drag or resize → Save → Done**. The toolbar starts the editing session, handles history and exposes Elements. Quick Edit holds the common size controls. The expanded workspace holds search, hierarchy, groups, profiles, settings and recovery.

## Baseline audit

The rescue builds on `feat/heavenly-axis-v3` at `e63d749bf0379f787ccc1c70fc6272881ca5028c`. Its original build and seven headless suites passed 450 checks. The following targeted probes used the baseline modules and test doubles with real input-handler calls and mocked Roblox geometry. Studio render results and the screenshots mentioned in the brief were unavailable.

| Priority | Baseline finding | Evidence |
| --- | --- | --- |
| P0 | Touch availability always selected the full-width bottom panel. The inspector reserved 232 units of chrome on tall viewports and at least 164 on compact ones. | The layout mock produced 1520 × 364.7 with a 132.7-unit body at 1536 × 695. At 640 × 360 it produced 624 × 234 with a 70-unit body. Three 48-unit labels preceded controls, so the initial view could contain only introductory content. Many list children shared the same default `LayoutOrder`. |
| P0 | Direct drags started before users crossed a motion threshold. The fixed-range slider wrote on press. | A one-unit diagonal touch jitter moved the target by (1, 1) and completed an action. Pressing at 25% of the old slider instantly changed a 100-unit target to 140 before any movement. |
| P0 | Canvas selection used the first raw hit. Eight large handle targets overlapped on small controls. | The discovery mock returned the broad parent first when the engine result listed it first. The layout mock placed all eight hit targets over the center of a 22-unit button. Actual native hit delivery still needs Roblox validation. |
| P0 | A resolved profile was saved as the chosen layer, and applying a broad-layer preview removed specific activation slots. | Mocked save copied an unchanged experience-inherited target into a place profile. Applying the experience preview removed the active place slot. |
| P0 | A pending stabilization observation could be replaced by a later operation. Gesture finalization and property verification could disagree. | Source-level finding in `Transform:_stabilize`, `Transform:_queueOperations` and `App:endGesture`. The transaction regressions exercise delayed geometry and rollback. |
| P1 | Input comments attributed coordinate agreement to `IgnoreGuiInset`. Overlay positions and device bounds still needed explicit origins. | Roblox documents a shared Core UI inset origin for `InputObject.Position`, `GuiBase2d.AbsolutePosition` and the hit-test API. Overlay placement and safe-area sizing cross distinct API boundaries. [GuiBase2d API source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiBase2d.yaml), [GuiService inset reference](https://create.roblox.com/docs/reference/engine/classes/GuiService#GetInsetArea) |
| P1 | Several UI refreshes rebuilt state outside their triggering concern. The discovery list recomputed visibility and sorting on each request. | Source-level findings in `UI:refresh`, `UI:refreshElements`, `App:_discoveryChanged` and `Discovery:list`. The controlled fixture includes an optional 240-object collection for runtime measurement. |

## UI architecture decision

Use retained native Roblox instances, reusable control builders, a pure layout planner, and explicit adapters for input, safe-area placement and HUD transforms. Native `GuiButton`, `ScrollingFrame` and `TextBox` preserve the engine's touch events, scroll inertia and keyboard focus. The editor controls canvas ownership, ranks game HUD candidates and updates the selection overlay independently. The design uses existing Roblox fonts, local shapes and no runtime asset fetch. [Roblox UI](https://create.roblox.com/docs/ui), [Roblox scrolling frames](https://create.roblox.com/docs/ui/scrolling-frames), [ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui), [GuiObject](https://create.roblox.com/docs/reference/engine/classes/GuiObject)

| Approach | Fit for this editor |
| --- | --- |
| Native Roblox UI | Direct access to native focus, safe areas and scrolling. Reusable surfaces and a pure responsive plan cover the required flexibility. Retained instances support targeted updates and preserve the existing single-file build. The editor owns component lifecycle and state updates. |
| Fusion | MIT-licensed declarative construction and reactive updates fit retained Roblox widgets. Pointer capture, hit priority, safe-area conversion and responsive design still need editor logic. Integration would add a vendored runtime, loader support and maintenance. [Fusion repository](https://github.com/dphfox/Fusion) |
| React Luau | MIT-licensed React lifecycle, component composition and ReactRoblox rendering are suitable for larger declarative UI trees. Adopting them here adds reconciliation and multiple packages. Roblox touch, viewport and input lifecycle behavior still comes from the engine and editor. [React Luau repository](https://github.com/Roblox/react-luau) |
| Vide | MIT-licensed fine-grained reactive bindings express native properties and events concisely. The editor still supplies capture, keyboard behavior, layout rules and state synchronization with target instances, with an added library to bundle. [Vide repository](https://github.com/centau/vide) |
| Iris | MIT-licensed, self-contained immediate-mode widgets are suited to diagnostic tools. A frame-driven editor widget connection would add continuous processing and a custom surface model to the core touch workflow. [Iris repository](https://github.com/SirMallard/Iris) |

The source bundle carries no UI dependency or license additions. These framework comparisons are based on their documented APIs and source repositories. Performance and touch behavior still need measurements in the target client.

## Evidence boundaries

The execution host runs Debian Linux. Roblox distributes Studio for Windows and macOS, and this environment had neither a supported Studio installation nor a physical Android device. The headless checks exercise Luau compilation, portable state, deterministic builds and mocked input/GUI behavior. Rendered appearance, device-safe geometry, physical touch delivery and executor compatibility require runtime evidence. [Studio setup](https://create.roblox.com/docs/studio/setup), [Studio device simulation](https://create.roblox.com/docs/studio/testing-modes#device-simulation)

See [verification results](VERIFICATION.md) for the acceptance gates and [the Studio and Android protocol](TESTING.md) for reproducible runtime checks.
