# Final refinement audit — 1.2.0

The owner reports the 1.1 interface, match history, player records, ability icons/tables and statistics working in ESO. The changes below have local regression coverage; **the new keybinding and capture behavior have not been live-tested by the developer**.

## Changed files

| Files | Purpose |
| --- | --- |
| `Keybindings.lua`, `Bindings.xml` | Localized native toggle action; guarded native assignment display; no default key or custom keyboard capture |
| `BattlegroundDossier.txt`, `Core.lua` | Load binding strings before XML; version 1.2; participant-key/confidence and neutral relationship handling; schema stays 1 |
| `API.lua` | Preserve every exposed slot; resolve exact within-match identity evidence; dynamic team/result fallbacks; completeness/team-size annotations; localized zone name; bounded observations from verified identity aliases |
| `MatchTracker.lua` | Collect across the verification window; persist/flush candidates; retain earlier participants and known values; deduplicate completion; save-time diagnostics |
| `PlayerDatabase.lua` | Stageable encounter updates; correct first/last-seen ordering; clean missing account display; unavailable observations remain unavailable |
| `Storage.lua` | Shared saved-ID guard; stage touched profiles/lifetime totals before publishing; no destructive migration |
| `UIData.lua`, `UIViews.lua`, `UIDossier.lua`, `UI.lua`, `UIStatistics.lua` | Preserve the design; accurate capacity/final-roster labels, unresolved identity/team display, localized names, debug counts and keybinding instructions |
| `tests/*`, `tools/package.py`, README/API notes | Regression cases, XML/manifest validation, XML packaging and documentation |

`CombatTracker.lua`, native combat-event registration/filters and `/bgd` command handlers remain unchanged. Existing UI controls, fonts, palette, pooling, sorting, search, scrolling, ability IDs and comparison workflows remain in use.

## Capture trace and fixes

1. **Completion:** only `BATTLEGROUND_STATE_FINISHED` starts capture. `POSTROUND` does not save. Local session IDs persist across reload, with existing saved IDs checked before any profile/statistic update.
2. **Exposure:** `GetNumScoreboardEntries(roundIndex)` supplies raw counts. Previously `Roster` omitted unnamed slots. It now returns one participant row for each exposed slot, including unavailable names. There is no expected-format-size gate and no nonzero-statistics requirement.
3. **Identity:** the old union rejected an entire match on duplicate/unresolved identities. New match-local participant keys retain such rows with unresolved confidence. Account and exact character-only keys still build lifetime profiles when unambiguous. Colliding account/character keys do not receive inferred profile merges or observed abilities.
4. **Late identity:** a unique exact character explicitly associated with an account in another read/round can be resolved within that match. Similar names do not match. Existing historical character-only profiles are not rewritten or merged. If combat was observed under both verified within-match identity keys, their disjoint event summaries are combined without counting the same cumulative snapshot twice.
5. **Fields:** the previous snapshot rejected all participants if any player lacked core statistics, team or final result. It now saves trustworthy rows and nil values, marks unavailable information, and continues trying for better data. Numeric zero remains zero. Later numeric corrections replace earlier values; earlier values retained after a missing read carry provenance and a partial marker.
6. **Timing:** previously three stable seconds could permanently commit before a later participant update. Capture now listens for the full bounded 30-second window. A nonempty candidate is persisted in the active session; leaving, deactivation, scoreboard clearing or a new session flushes it once with an early-verification marker. A UI reload can resume a persisted candidate/deadline; deactivation may instead safely flush it before reload.
7. **Earlier participants:** round rosters are unioned by safe identity, and earlier final-window participants who disappear remain as explicitly retained rows. Their last exposed statistics are not synthesized. Current-round exposed/captured counts remain separately available from total retained participants.
8. **Publication:** previously profiles were incremented before the match was published, so a derivation error could leave partial aggregate changes. Copies of touched profiles and lifetime statistics are now prepared under `pcall`; history/counters are published only after successful derivation. Repeated completion and reload cannot increment the same saved ID again. Pruning still changes details/references only, not lifetime totals.
9. **Unavailable observations:** previous lifetime merging converted a missing healing/damage field into zero. Merging now adds a field only when a numeric observation exists.
10. **Presentation:** the roster and dossier previously called unresolved teams opponents. Relationship checks now require known teams and neutral styling handles unknown relationships. Missing/empty account strings no longer hide a known character name in player lists. Final roster sizes are shown independently of nominal format capacity.

## Diagnostics

`/bgd debug on` enables one capture summary using actual stored values:

```text
Scoreboard entries: … | Final round captured: … | Participants saved: …
| Account identities: … | Character-only: … | Unresolved: … | Retained earlier: …
```

Partial fields or exposed/captured mismatches add a debug warning. A saved scoreboard also shows capture counts in debug mode. Normal gameplay does not emit these diagnostics. Counts include the local player; lifetime profile creation excludes that local entry. A retained leaver or an earlier-round substitute can make saved participation exceed the latest round's exposed count without being a mismatch.

## Native binding

Sources: [ESO's native binding declarations](https://github.com/esoui/esoui/blob/live/esoui/ingame/globals/bindings.xml), [native keyboard binding UI](https://github.com/esoui/esoui/blob/live/esoui/ingame/keybindings/keyboard/keybindings.lua), and [API 101051 documentation](https://github.com/esoui/esoui/blob/live/ESOUIDocumentation.txt).

The general layer declares a `BGD_TOGGLE` action under the localized Battleground Dossier category. `SI_BINDING_NAME_BGD_TOGGLE` supplies **Toggle Battleground Dossier**. `Keybindings.lua` registers strings before XML; the handler calls `B.UI:Toggle()` only after the UI exists. No `CreateDefaultActionBind`, protected bind/unbind call, key listener or mandatory library is added.

Configure **Settings → Controls → Keybindings → Battleground Dossier → Toggle Battleground Dossier**. Assignment display uses guarded `GetActionIndicesFromName`, `GetMaxBindingsPerAction`, `GetActionBindingInfo` and `GetKeyName` calls, including modifier keys and binding slots. Unknown results display instructions rather than a guessed shortcut. No direct settings-menu navigation method was verified for safely selecting this custom category, so no speculative button was added.

## Storage compatibility and bounds

The account-wide SavedVariables name/version and schema **1** remain unchanged. All new fields are optional annotations: match-local participant ID/confidence/slot, diagnostic counts, partial/provenance flags, nominal versus final team-size data, localized zone name and one active capture candidate. Old histories remain valid without them, and no historical player keys are changed.

The original retention/profile/ability/alias limits remain. Round queries retain the existing 100-entry sanity ceiling; up to twenty earlier rosters and the current roster are inspected. Earlier-read retention is capped at 2,100 rows, while the current exposed roster is preserved. Such exceptional truncation is marked partial. No raw combat event stream or unbounded retry queue is stored.

The old Battleground name and ID remain available internally and in history tooltips. A verified active Battleground may also expose `GetUnitZone("player")`; this localized zone is preferred for display. A zone may be broader than a particular arena/ruleset. Without it, the original string is retained verbatim, including raw-looking names. Historical names cannot safely be cleaned after the client has discarded their context.

## Verification performed

`python tests/run.py`: **81 Lua 5.1 cases pass** — 33 existing core cases (expectations updated for deliberate partial-capture/timing changes), 22 UI cases, and 26 new reliability/keybinding cases. All 15 Lua modules load in manifest order. Native keybinding XML and its action/category are parsed, manifest references checked, and forced default bindings rejected by the local checks. `python tools/package.py` builds the independent addon including `Bindings.xml`.

New coverage includes 8-player 4v4, 6-player Competitive 3v3, 18-player 6v6v6 and 9v9, uneven 3v2, zero-valued statistics, missing accounts/names/teams, similar character names, late arrivals, disappearing players, substitutes/multiple rounds, repeated completion, partial flush, persisted candidates across reload, within-match account resolution, observation integrity, failed-derivation rollback, old records, late corrections, actual diagnostics and native keybinding assignment/delegation.

## Remaining limits

- No permanent server match ID or definitive “all final fields complete” event was verified. Local deduplication applies to the persisted session and saved record IDs; a truly different session cannot be identified from a map ID alone.
- Capture cannot recover a participant the client never exposes. A completely empty final scoreboard produces no completed record. A server update after the bounded window cannot be guaranteed to be included.
- Unnamed/ambiguous rows cannot always be matched reliably across reordering or rounds. They remain explicitly unresolved and do not contaminate permanent profiles. Retained entries do not establish concurrent team sizes or private identities.
- Numeric API-supplied zero cannot be distinguished from a mode-irrelevant API zero. Unsupported/nil calls remain unavailable. Earlier-round cumulative-statistic/leaver behavior and shutdown event ordering still need client validation.
- A crash before ESO writes SavedVariables can lose in-memory changes; the addon cannot force a disk save. The staged publication guard protects ordinary Lua derivation errors, not client/process termination during persistence.
- Native key combinations, category visibility, localized zone display and new final-window behavior need in-game verification. Existing user-reported success is not presented as live testing of this new patch.

## Short in-game checklist

1. Update over the existing addon folder, keeping SavedVariables. Reopen an older match, player profile and ability table; verify the previous history/counter totals are unchanged.
2. Assign **Toggle Battleground Dossier** in native Controls. Test the shortcut to open and close the window, including a modifier combination; verify `/bgd` still works and no default key was imposed.
3. Inspect Settings → Keybindings and confirm the assignment or clear fallback instructions. Check the established navigation, hover states, scrollbars, dossiers and long names remain usable.
4. With `/bgd debug on`, complete a full or understaffed game. Compare final native scoreboard entries with saved rows and diagnostic identity counts. A six-player Competitive 4v4 should show a 3v3 final roster without being treated as invalid.
5. Check a zero-stat participant and any missing-account/team case exposed naturally; confirm retained match rows and honest unavailable/neutral labels. Do not interpret unresolved rows as enemy profiles.
6. Complete a multi-round match and, where possible, one with a leaver/substitute. Expect one save after verification or a marked partial save on early departure. Check team results, retained rows and late updates against ESO's scoreboard.
7. Reload at the final scoreboard, then reopen history outside the Battleground. Verify one record and one encounter increment per known opponent/teammate, not duplicate totals.
8. Compare localized displayed map/zone names with the original-name tooltip. Disable debug afterwards. New live verification is still required; no test here certifies native drawing or server timing.
