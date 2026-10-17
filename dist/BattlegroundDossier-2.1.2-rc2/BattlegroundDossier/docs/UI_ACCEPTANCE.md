# UI refinement 1.1 — verification and acceptance

Historical checklist for the 1.1 UI overhaul. The owner has since confirmed that UI working in ESO. For the 1.2 keybinding/capture changes and current verification status, see [RELIABILITY_AUDIT.md](RELIABILITY_AUDIT.md); its file-change/compatibility notes supersede the 1.1-only scope below.

The project owner has confirmed that the original addon loads in ESO, opens its interface, records matches and players, persists data and records attributed combat effects (including ability IDs, event counts and damage). This update preserves that implementation. **The redesigned UI has not been visually verified in ESO by the developer.**

## Scope and compatibility

- `MatchTracker.lua`, `CombatTracker.lua`, `PlayerDatabase.lua`, `Storage.lua` and `API.lua` remain byte-for-byte unchanged from the working baseline.
- Addon identity, `/bgd` commands, SavedVariables name, SavedVariables version and storage schema **1** remain the same.
- Optional `settings.presentation` fields are added on demand: `compactNumbers`, `abilityIcons`, `defaultTab`. Missing fields default safely; no match/profile conversion or history reset occurs.
- UI modules: `UIData.lua` contains read-only projections, `UIComponents.lua` contains theme/pooling/tables, `UI.lua` owns the shell/navigation, `UIViews.lua` contains match/player lists, `UIDossier.lua` contains dossiers/comparison/abilities, and `UIStatistics.lua` contains statistics/settings.
- Changes to data collection are not part of this release. New visuals operate entirely on the existing saved snapshots and profiles.

## Local verification

Run `python tests/run.py` with `lupa` installed. All 14 manifest-listed Lua files load under Lua 5.1, followed by the original 33 regression cases and 22 UI cases. UI cases test:

- Exact/compact formatting, unavailable values and sorting with missing statistics.
- Combined result/mode/format/identity filters and native-dropdown callback adapters.
- All 18 scoreboard rows, three-team filtering, fixed column geometry and scrollable roster extent.
- Whole-row selection, contextual dossier tabs, comparisons and preserved history navigation state.
- Ability ID fidelity, exact-value/timestamp tooltips, each ability sort column, neutral icon fallback and 205-entry pagination.
- Previous-match ability aggregation without losing distinct IDs or including later/current matches.
- Saved match/profile/statistic immutability across rendering, schema preservation and preference/position persistence.
- Empty/missing data, control reuse, visibility/combat-aware saved-data refresh, and confirmed reset/cancellation.

These tests use mocked controls, not ESO's renderer. Width checks establish consistent intended geometry; actual text/font sizes, wheel routing, draw ordering, focus and Escape behavior still require client testing.

## Practical in-game checklist

1. **Upgrade existing data:** log out to write SavedVariables, copy the addon update over the existing folder, then log in. Confirm the previous match count, encounter totals, ability IDs and records remain accessible. Do not use Reset for this check.
2. **Shell:** at 1920×1080, open `/bgd`; inspect all four tabs, selected/hover states, header/footer, close button and default 85% scale. Drag, close, reopen and `/reloadui`; confirm position and scale persist. Check 60%, 100% and 120% scale plus centring.
3. **History:** combine Result, Game mode and Format filters with a player/account search. Clear filters. Open a match on a later history page, visit a dossier, navigate to another main tab, then return to Matches; verify sensible search/page/scroll restoration.
4. **Scoreboard:** use an 18-player two-team or three-team record. Confirm all participants are reachable by the roster's native scrollbar, headers remain fixed within the table, numeric columns align and no controls extend past the panel. Hover exact values, sort each numerical heading both ways and test every team filter.
5. **Dossier:** click different parts of a row, check selected-row highlight after Back, and inspect Overview, Observed abilities, History and Scoreboard details. Confirm account/class/team/familiarity, missing values, all extra counters and medals remain readable.
6. **Abilities:** use a real record containing the known observed effects. Confirm IDs/event totals/damage match the original data. Verify icons correspond to exact IDs and unknown icons use neutral slots. Hover IDs/timestamps/exact values, sort all columns, scroll long lists and check This match versus Previous matches. Where the aggregate exceeds 80 IDs, use the ability page controls to reach the remainder.
7. **Player database:** search an account and an older character alias; open its dossier. Check team results, known characters/classes, retained match links, record totals and Lifetime versus Latest match observations. Confirm old abilities are clearly historical.
8. **Comparison:** select A and B from different roster rows; swap them and compare with yourself. Confirm positive/negative differences, nil placeholders and zero-death K/D. Verify abilities can be inspected for either side without implying an overall winner.
9. **Statistics/settings:** check lifetime counts and record cards, frequent-player links, trend sample tooltips and insufficient-history messaging. Change each appearance/behaviour setting and confirm it actually changes behaviour, including default tab after reload and compact-number/icon preferences.
10. **Focus and combat:** type into search, press Enter/Escape, close the window, and confirm chat/gameplay focus works normally. Confirm ESO's Escape handling dismisses the top-level window and opening it enables cursor interaction. Enter combat to check automatic hiding and complete another match to check refresh/auto-open behaviour.
11. **Empty/missing data:** test a separate fresh SavedVariables backup/installation or an empty test account. Check centred empty states in Matches/Players and no observations in a dossier. Do not delete the main history merely to test empty states.
12. **Protected reset:** only with a backup/test account, arm then cancel the settings reset; confirm nothing changes. Verify expiry after 30 seconds, then a deliberately confirmed reset. Existing slash reset confirmation should still work. Confirm reducing retention prunes only what the setting describes.

## Remaining visual risks

Localized or unusually long names may require hover to read in full; tables deliberately ellipsize single-line labels. Native tooltips preserve full identities and precise values. Multiple native scroll areas intentionally keep long rosters and ability tables bounded; wheel focus, scrollbars and controller/keyboard behavior require client testing. No gamepad-specific layout is provided.
