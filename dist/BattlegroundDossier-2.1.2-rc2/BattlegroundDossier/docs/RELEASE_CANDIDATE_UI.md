# UI stabilization: 2.1.2-rc2

## Targeted rc2 correction

The reported rc1 line 60 was the shared button mouse-enter handler. It called `button:GetText()` while checking whether an automatic tooltip was needed. ESO's ButtonControl exposes `SetText` and `GetLabelControl`, but **not GetText**; `GetText` belongs to LabelControl/EditControl. This was an invalid native method call, not a missing click callback, uninitialized utility or manifest-order problem. The error affected ordinary buttons without explicit tooltips; those with explicit tips previously short-circuited that branch.

The handler now obtains `local label = button:GetLabelControl()`, reads `local text = label:GetText()` and measures that same label. This fixes the call rather than hiding it behind a nil check. `Controls:Button` constructs a CT_BUTTON, sets its font/text, then installs the handler. The same helper supplies navigation tabs, pooled settings/role buttons and sorting headers, so they all receive the correction. Other runtime GetText calls were reviewed: they target labels or native editors. Dropdown/native EditBox setup and manifest order remain unchanged.

The test mock previously gave every control a GetText method, incorrectly masking the unsupported Button call. It now returns nil for ButtonControl:GetText and synchronizes Button:SetText/SetFont with the button's label, matching the relevant native contract. Test button lookup helpers now read through the label as well. New cases reproduce the unsupported method, exercise short/long/rebound/explicit-tip hover and click callbacks, hover shared buttons on every major screen, and verify history layout/data preservation.

PLACE was removed only from `UIViews:History` columns. The existing shared fitter allocates its 55 logical units to the flexible Battleground-name column (315 instead of 260 at the current window width). Seven headers/cells fill the existing table width; reused extra cells are hidden. Saved `match.placement`, capture/result/statistic calculations, scoreboard placement and the existing tooltip remain unchanged. Row click/navigation and scrolling use the same implementation.

Files changed for rc2: `UIComponents.lua`, `UIViews.lua`; version fields in `Core.lua`/`BattlegroundDossier.txt`; `tests/eso_mock.lua`, `tests/ui_spec.lua`, `tests/merge_spec.lua`, `tests/personal_spec.lua`, `tests/production_ui_spec.lua`; and `README.md`, `docs/API_VERIFICATION.md`, this document. No tracking/storage/calculation module, native binding or runtime initialization was changed.

**172 offline Lua 5.1 tests pass**, including the existing simulated typing/Backspace tests and three new regressions. All 20 runtime Lua modules compile/load; manifest/bindings and ZIP contents validate. There has been no live-game test of rc2 by the developer.

In ESO, verify version **2.1.2-rc2**, then hover/click every main tab and a numeric +/- control. Open Statistics/BG History, select a role, hover sorting headers and open dropdowns; confirm no hover Lua error. Check numeric replacement/Backspace/Enter/Escape. Verify seven Match History columns with no PLACE or gap, open a row and confirm placement still appears in details. Finally open a player profile and check the HUD/AP/rank remains functional. The broader rc1 checklist below remains useful for native keyboard and visual verification.

## Prior rc1 input/layout changes

This candidate implements the numeric input correction and a shared visual pass. **Physical keyboard interaction and native rendering have not been tested inside ESO by the developer.** Compilation and simulated controls do not establish that release-blocking keyboard behavior is fixed in the running client. Complete the short checklist below before treating this build as verified for release.

## Numeric input investigation

The previous implementation created a real `CT_EDITBOX`, not a label. However, it did not inherit the native keyboard EditBox template and supplied no mouse-down handler to call `TakeFocus()`. Mouse-enabled/hover styling and focus callbacks alone do not establish click-to-focus routing. ESO's [ZO_DefaultEdit template](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/editboxtemplates_keyboard.xml) explicitly calls `self:TakeFocus()` in `OnMouseDown`. The [native enabled helper](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/editboxtemplates.lua) likewise uses that handler when enabling editing. Earlier mocks bypassed the faulty path by calling TakeFocus/SetText directly.

The shared component now instantiates `ZO_DefaultEdit` and explicitly enables keyboard input, editing, copying and pasting. Native cursor movement, selection, Backspace, Delete and Ctrl+A remain the client's responsibility; the addon implements no custom key recorder or label-based editor. Numeric fields select all on initial focus, and the entire value cell can focus its editor. Search uses the same native configuration. A hidden label measures font width only: it never displays or simulates editable text. EditControl has no documented horizontal-alignment setter, so a measured native editor is centered within the value cell instead of calling an invented method.

The per-text-change callback only measures/repositions that editor. It does not SetText, validate, save, prune or rebuild the view. Enter validates/commits; Escape cancels; blur validates/commits or reverts. Invalid/empty/out-of-range input restores the previous setting. Existing minimum, maximum and step rules remain unchanged. Direct commits update the field and button states without rebuilding Settings, preserving native focus when clicking the next editor. The existing visible-data refresh updates dependent summaries once no numeric field is active. Closing/navigating cancels unfinished edits as before.

Other investigated paths:

- There was no numeric OnUpdate/reset-on-keystroke handler. Passive saved-data refresh already paused for numeric edits and still does.
- An old search debounce timer could outlive a tab switch and redraw Settings; navigation now cancels it.
- Search rerenders previously wrote its normalized saved query back into the focused editor; a focused search now retains its literal unfinished text.
- Addon toggle actions ignore activation while an addon text editor owns focus. Existing native binding definitions and assignments remain unchanged.
- No parent keyboard listener or custom Backspace/Delete handler was introduced. Native EditBox handlers own editing. Explicit edit/copy/paste/keyboard configuration avoids relying on bare-control defaults.

## Shared visual changes

`Controls.layout` centralizes input/button heights, stepper dimensions/gaps, header/row heights, padding and scrollbar clearance. The numeric field has a dark inset, a muted-gold focus border, equal-width +/- buttons and equal gaps on both sides. Bounds disable the corresponding step button with native disabled styling; reuse restores enabled states. Buttons use centered text, native single-line ellipsis, normal/hover/selected/disabled colors and a restrained pressed offset. Long button text gets a tooltip when truncated. Pagers now visibly disable unavailable directions.

Cards center both headings and values within existing measured, padded bounds. Long readouts fall back to the existing readable game-bold font before truncating; complete values remain in tooltips. Headings, comparisons, dossiers, role summaries and data-capacity cards use the same component. No statistics were recalculated for styling.

Table headers and cells share one alignment resolver: compact K/D/A, encounter counts, team/placement and record fields center; longer damage/healing and other totals align right; names remain left. Standard rows are 44 logical units, headers reserve 40, and the scrollbar gutter remains separate from data. Slightly wider K/D/A cells accommodate sort arrows without consuming the flexible player-name column. Existing sorting, filtering, row selection and every data column remain. Truncated values append their full text to row tooltips when the existing tooltip does not already include it; tables without custom tooltips receive exact raw values by default.

Toolbar labels and controls now have explicit top/bottom padding and aligned baselines. Search/input/button heights agree. The main window remains a fixed 1180×800 logical layout; it does not add resize handles. Requested scale remains saved unchanged, while rendered scale fits current GuiRoot dimensions, including the game's own UI scaling. One named screen-resize listener updates this fit; there is no new polling loop.

The live HUD retains its four-column appearance, position/preferences and visibility modes. Its captions/readouts now have explicit measured heights and a gap, allowing the bar to grow only if native font metrics require it. Large readouts use an existing smaller readable font when needed. `BG RANK*` marks a cached rank during refresh, replacing the longer caption that could crowd its cell. The tooltip explains the marker. Rank/AP/result calculations are unchanged.

## Files changed in this pass

- `UIComponents.lua`: native editors, focus/style helpers, centered readouts, common geometry, table alignment/tooltips, button states.
- `UIStatistics.lua`: symmetrical steppers, no immediate redraw during direct commits, bounded button states, screen-fit scale application.
- `UI.lua`: toolbar padding, fit-to-screen scale, focused-search protection, search-timer cancellation and pager state.
- `UIViews.lua`: standard match-row height and slightly wider compact scoreboard columns.
- `UIPersonalHistory.lua`: compact column widths and disabled personal-history pager boundaries.
- `UIDossier.lua`: disabled observed-ability pager boundaries.
- `LiveSessionHUD.lua`: explicit font bounds, readout fitting and shorter cached-rank label.
- `Keybindings.lua`: ignore addon toggles while an addon editor has focus.
- `Core.lua`, `BattlegroundDossier.txt`: release-candidate version only; manifest module order is unchanged.
- `tests/eso_mock.lua`, `tests/production_ui_spec.lua`, `tests/merge_spec.lua`, `tests/run.py`: simulated native click/focus/edit commands and regression coverage.
- `README.md`, `docs/API_VERIFICATION.md`, this document and `tools/package.py`: usage, evidence, release gate and packaging.

## Data and regression verification

**169 offline Lua 5.1 scenarios pass**, comprising the previous 150 plus 19 production UI cases. Every manifest-listed Lua module compiles and loads; binding XML/loading order and install ZIP integrity are checked. Added cases exercise click-to-focus, select-all/replacement, Backspace, Delete, cursor insertion, paste, valid Enter, invalid commits, Escape, next-field focus transfer, all six numeric settings, absence of typing-time pruning/rerenders, focus feedback, keybinding guards, centered steppers/cards, alignment, exact tooltips, search debounce/navigation, all major views at normal scales, root-size fitting and HUD bounds.

The mock now distinguishes a bare EditBox from one inheriting native click-to-focus behavior and routes simulated editing commands only to an enabled focused editor. This is stronger regression evidence than assigning strings directly, but is not an ESO executable or a substitute for physical client testing.

Compared with the shipped 2.1.1 ZIP, `Storage.lua`, `API.lua`, `PlayerDatabase.lua`, `MatchTracker.lua`, `CombatTracker.lua`, `LiveSession.lua`, `LiveSessionCore.lua`, `PersonalHistory.lua`, `BattlegroundDossier.lua` and `Bindings.xml` are byte-for-byte unchanged. Thus no capture, statistics, player identity, persistence, AP/rank or match lifecycle code is replaced by this pass. SavedVariables versions/schema remain 1. The original tracker reference remains untouched. Existing logs, profiles, role annotations, preferences and history are retained.

## Required in-game release check

1. Install the candidate and verify **2.1.2-rc1** in Settings diagnostics. Open Settings, click retention `200`, press Ctrl+A, type `500`, press Enter and confirm the setting changes. Then physically test cursor placement, Backspace, Delete, paste and a second edit in the same field.
2. Repeat for all numeric controls, including decimal main/HUD scale and opacity. Verify selecting another field commits once and leaves the second field editable; test Enter, Escape, invalid/empty/out-of-range values, +/- and disabled bounds.
3. Type retention `1000` slowly. Confirm history/settings do not change during `1`, `10`, `100`, or `1000` until committed. Test reductions only on a backed-up installation; verify a deliberate commit prunes once. Reload and confirm the chosen setting persists.
4. Search, then immediately switch to Settings and type. Check no delayed redraw resets the editor. Test assigned Dossier/HUD keybindings outside editing and confirm typing into inputs does not toggle either window.
5. Review Matches, Players, every dossier tab, comparisons, Lifetime overview, BG History in all three roles and Settings at scales 0.6/0.85/1.2. Check centered cards/counts, long names, full-value tooltips, sort arrows, dropdowns, scrollbars, pager bounds and focus/hover/selected states. Change resolution/game UI scale and confirm screen fit without changing the saved requested scale.
6. Inspect the HUD's W/L, percentage, rank/cache marker and AP readouts with header on/off. Check Always Visible/Battlegrounds Only, manual toggles, drag/lock, and entry/postgame/exit behavior. Confirm normal tracking, previous matches/profiles/observations and both native bindings still work.

Do not mark physical keyboard acceptance or native visual verification complete based solely on the automated tests.
