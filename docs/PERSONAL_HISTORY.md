# Personal history and UI refinement: 2.1.0

Open `/bgd stats`, then **BG History**. The existing **Lifetime overview** remains available beside it. This update builds on the existing UI, recording lifecycle and SavedVariables rather than introducing a second match collector.

## Personal history

Select a recorded character, a display role (**HEALER**, **TANK**, **DPS**) and **Last 10 / Last 25 / Last 50 / All retained matches**. The window remembers role and range per character; the Statistics subview also persists. Character selection defaults to the logged-in character after login/reload. The role changes which metrics are emphasized; it does not infer a build, assign roles to matches or filter out matches played in other roles.

General summaries show retained matches in range, team W/L/D, resolved win percentage, recorded streak, average K/D/A and the ten newest results. Draws count in the win-rate denominator; unresolved outcomes do not. Streaks describe consecutive recorded results within the selected range, not an uninterrupted lifetime streak. Missing records, unassigned characters and pruned details limit that claim.

- **HEALER:** total/average/best healing, damage context, healing averages in wins versus losses, best healing/assist match links and recent healing trends.
- **DPS:** total/average/best damage, total/highest kills, aggregate K/D, best damage/kill match links and recent damage trends.
- **TANK:** deaths/assists, real damage and damage-taken fields, shields granted when recorded, separate objective summaries, lowest recorded deaths and recent survival averages. No blocked damage, mitigation or inferred defensive ratings are invented.

Objectives are grouped by their saved unit/meaning. Captures, ball-carry seconds and Deathmatch's native damage-taken column are never added into a single objective total. Legacy objective values with no saved label appear separately by mode as unspecified. Missing fields remain unavailable, while legitimate zeroes contribute to averages. Each average uses that field's available samples; tooltips show sample counts. Aggregate K/D uses only matches containing both K and D and is unavailable when the paired death total is zero.

The personal match table is newest first by default, supports sortable headings and exact-value tooltips, and uses a fixed-height native scroll container. Forty-row pages keep control allocation bounded; every retained match remains accessible. Click a row or best-performance record to open the existing scoreboard. Back returns to personal history with role, range, page, sorting and scroll preserved. Mode/format breakdowns and two-period averages use the same selected character/range. A missing previous period stays unavailable.

At the bottom of a saved scoreboard, **PERSONAL MATCH ROLE** lets you manually annotate that match as Healer, Tank, DPS or Unclassified. Older matches stay unclassified. The annotation appears in personal history but never changes the independently selected display role.

## Attribution and data preservation

`PersonalHistory.lua` derives statistics from retained snapshots without changing them. `UIPersonalHistory.lua` renders the new view using existing controls. World plus saved local character ID is the strongest owner key. Older records can use the exact normalized saved local character name, or a uniquely flagged local roster entry. A unique isLocal entry identifies statistics; when flags are absent, only a unique exact match to the explicitly saved local character can be used. Duplicate local flags or an ambiguous-local marker suppress personal statistics rather than selecting another player.

Legacy name-only owners can be associated with an ID only when that name is linked to exactly one observed character ID on that server. Competing IDs leave the legacy name group separate. Account display names never combine different local characters. Observed renames on the same saved ID remain associated. Records without a trustworthy local owner remain accessible in Matches and are excluded from character summaries. Records with a known owner but missing/ambiguous roster entry keep their saved outcome and show unavailable personal fields. Duplicate match IDs are counted once in derived history.

The ESO SavedVariables version and main schema remain **1**. Lazy, additive preferences use `settings.personalHistory = { version = 1, characters = ... }`, bounded to 128 character entries. Overflow characters use temporary defaults without evicting existing settings. Unsupported future preference versions are retained and disable only this view. Optional `match.personalRole` annotations live with retained records and disappear when those details are pruned. No new lifetime sums are synthesized from missing/pruned detail; the existing account-wide lifetime aggregates retain their original meaning. Match tracking, combat attribution, encounter aggregation, session HUD and rank/AP logic are unchanged by this pass.

## Numeric settings

Every +/- numeric setting, including independent HUD scale/opacity, now has a native edit box. Clicking selects the number. **Enter** commits; **Escape** restores the previous value. Focus loss validates and commits or reverts. Closing or rebuilding the view cancels an unfinished edit. Automatic saved-data refresh pauses while a numeric edit is active.

Typing never changes settings or prunes history. Only a completed valid edit invokes the existing setting callback. Invalid, empty, negative and out-of-range entries revert. Use plain numbers (for example `10000`, not `10,000` or `10K`); decimals are accepted for fractional settings. Values round to the setting's existing increment, with exact minimum/maximum endpoints preserved. The minus/plus buttons keep their existing step/clamp behavior and synchronize the field. Reducing match retention on a completed commit still prunes detail immediately, as before.

## Shared visual fixes

- Cards reserve twelve logical units on every side and measure font heights for separate label/value regions. Section headings and settings rows also reserve explicit text/panel padding. Values and long labels retain tooltips.
- Table headers and cells use the same column geometry, inset and alignment. Numeric fields align right, names left, and categorical team/record fields center. Narrow K/D/A columns use smaller insets; the scrollbar has a reserved gutter.
- Column layout consumes available table width. The scoreboard reserves readable widths for other fields and gives remaining width to PLAYER (about 410 logical units at the current fixed window width, formerly 240). All columns share an adaptive fit calculation; important full names and exact values remain in row tooltips. The main window remains fixed-size and scalable, with no new resize handles.
- Character names use ESO's `zo_strformat(SI_UNIT_NAME, rawName)` for display, including older records and profile aliases. If unavailable, only terminal `^Mx`/`^Fx` markers are removed. Raw names, account strings and persistent identity keys are not rewritten. Existing normalization already treats raw/formatted character names equivalently, so this display fix does not create new profiles or require a merge. No historical profiles are automatically merged or rekeyed.

## Validation

**142 offline Lua 5.1 scenarios pass:** 112 existing cases plus 30 personal-history/polish cases. All twenty manifest-listed Lua modules compile and load. Tests cover deferred numeric commits/pruning, Escape/blur, +/- synchronization, HUD settings, native formatter delegation, stable identity preservation, exact fallback names, padded card bounds, adaptive widths/alignment, character/server isolation, legacy ownership/renames, duplicate IDs, sample-aware statistics, objective units, streaks, date sorting, role/range persistence, pagination, drilldown/Back, future preference versions, pruning and bounded control reuse. These checks cannot certify native font rasterization or actual keyboard/cursor behavior in ESO.

### In-game checklist

1. Back up SavedVariables with ESO closed, update addon files, then open old matches/profiles. Confirm counts, observations, AP/rank HUD and both keybindings still work.
2. In Settings, click each numeric field. Type a value, test select-all, Enter, Escape, invalid input and click-away. While typing `1000` into retention, verify no detail disappears. Test an intentional reduction only with a backup. Check +/- and the independent HUD scale/opacity fields.
3. Inspect cards and table headers at scales 0.6, 0.85 and 1.2. Verify padding, header arrows, right/center alignment, scrollbar gutter and long/localized names. Existing `^Mx`/`^Fx` names should display cleanly and remain searchable; account strings should remain unchanged.
4. Open Statistics → BG History. Select each role, range and character; compare summaries with known local scoreboard rows. Check missing fields, real zeroes, draw/unresolved outcomes and separate objective units.
5. Sort the personal table, scroll/page, open a row and use Back. Annotate a match role; confirm other matches remain unclassified and display role stays independent. Reload and change characters to verify role/range persistence and separation.
6. Complete an understaffed/full/multi-round match. Confirm existing capture still saves once, the correct character's personal history updates, and the integrated session HUD still counts only the single finalized result.

No live-game testing of this update has been performed by the developer.
