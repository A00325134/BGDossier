# API verification notes

Target: ESO API **101051**. Reviewed against the ESOUI repository's `live` branch during implementation. These links are primary client UI/documentation sources; they can change with later releases.

- [API documentation](https://github.com/esoui/esoui/blob/live/ESOUIDocumentation.txt)
- [Native Battleground scoreboard](https://github.com/esoui/esoui/blob/live/esoui/ingame/battleground/battlegroundscoreboard.lua)
- [Native scroll control templates](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/scrolltemplates.xml)
- [Native scene manager / top-level and Escape handling](https://github.com/esoui/esoui/blob/live/esoui/ingame/scenes/ingamescenemanager.lua)
- [Native combo box template](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_combobox/zo_combobox.xml) and [base methods](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_combobox/zo_combobox_base.lua)

No third-party addon code was copied. The adapter isolates optional calls behind guarded `pcall` and returns nil for absent functions/errors. Critical missing data prevents capture. Native UI dependencies are loaded by ESO before addons.

## Verified signatures used

| API/event | Contract used |
| --- | --- |
| `GetNumScoreboardEntries(roundIndex?)` | Number of entries for that round |
| `GetScoreboardEntryInfo(entryIndex, roundIndex?)` | characterName, displayName, team, isLocalPlayer |
| `GetScoreboardEntryClassId(entryIndex, roundIndex?)` | Class ID |
| `GetScoreboardEntryScoreByType(entryIndex, scoreType, roundIndex?)` | Numeric scoreboard statistic |
| `GetBattlegroundCumulativeScoreForScoreboardEntryByType(entryIndex, scoreType, roundIndex?)` | Native aggregate-view statistic |
| `GetCurrentBattlegroundState()` | State enum; only `FINISHED` saves |
| `EVENT_BATTLEGROUND_STATE_CHANGED` | previousState, currentState (after event code) |
| `EVENT_BATTLEGROUND_SCOREBOARD_UPDATED` | No payload; reread scoreboard |
| `GetCurrentBattlegroundRoundIndex()` | Current round index, potentially nil |
| `DoesBattlegroundHaveRounds(battlegroundId)` | Whether native aggregate stats are appropriate |
| `GetBattlegroundNumTeams(id)` / `GetBattlegroundTeamByIndex(id, index)` | Dynamic team enumeration |
| `GetBattlegroundTeamSize(id)` | Reported team capacity, not actual participating count |
| `GetCurrentBattlegroundScore(roundIndex, team)` | Round team score; explicit round argument |
| `GetCurrentBattlegroundRoundsWonByTeam(team)` | Aggregate team rounds won |
| `GetBattlegroundResultForTeam(team)` | INVALID, WIN, LOSS, TIE |
| `GetCurrentBattlegroundGameType(roundIndex?)` | Round mode |
| `GetBattlegroundName(id)` | Map/name |
| `DoesCurrentBattlegroundImpactMMR()` | Competitive-filter flag; no private MMR read |
| `GetBattlegroundNumUsedMedals(id)` / `GetBattlegroundMedalIdByIndex(id, index)` | Bounded single-round medal enumeration |
| `GetScoreboardEntryNumEarnedMedalsById(entryIndex, medalId, roundIndex?)` | Single-round earned medal count |
| `GenerateCumulativeMedalInfoForScoreboardEntry(entryIndex, roundIndex?)` | Native cumulative medal iterator preparation |
| `GetNextBattlegroundCumulativeMedalId(lastMedalId?)` | Next cumulative medal ID |
| `GetBattlegroundCumulativeNumEarnedMedalsById(medalId)` | Cumulative medal count |
| `GetMedalName(medalId)` | Display name |
| `GetScoreboardEntryNumLivesRemaining(entryIndex, roundIndex?)` | Lives remaining, kept separately from cumulative totals |
| `GetAbilityProgressionXPInfoFromAbilityId(abilityId)` | hasProgression, progressionIndex, additional XP fields |
| `GetSkillAbilityIndicesFromProgressionIndex(progressionIndex)` | skillType, skillLineIndex, skillIndex |

`GetBattlegroundTeamColor` is a native **Lua UI helper**, not a C API entry. Its use is visible in the native scoreboard and is guarded with a neutral-color fallback. `GetBattlegroundTeamName` and `GetClassName` are documented APIs. The UI uses `ZO_ScrollContainer` and its `ScrollChild`/`Scroll` controls from native templates.

The main window is registered with `SCENE_MANAGER:RegisterTopLevel(control, false)` and shown/hidden through the scene manager. This supplies ESO's native cursor/menu mode and Escape behavior while keeping top-level bookkeeping consistent. Automatic opening is suppressed while `IsUnitInCombat("player")` reports combat.

`EVENT_COMBAT_EVENT` (after event code):

```lua
result, isError, abilityName, abilityGraphic, abilityActionSlotType,
sourceName, sourceType, targetName, targetType, hitValue, powerType,
damageType, log, sourceUnitId, targetUnitId, abilityId, overflow
```

Only damage, critical damage, blocked damage, DOT ticks/critical ticks, heal/critical heal and HOT ticks/critical ticks are accepted. Shielded damage is excluded because it cannot safely be added to dealt damage. Combat logging is registered only during running rounds, with early result/source rejection. Runtime source-name attribution is roster-based; opaque combat unit IDs do not link accounts. Ability categories use only successful progression metadata lookups, otherwise “Other observed effects.”

## Fidelity boundaries

- No permanent server match ID was verified. Local session IDs are persisted and deduplicated; there is no claim of globally unique server identity.
- Final scoreboard readiness is heuristic after authoritative `FINISHED`. Version 1.2 collects across a bounded 30-second window, or flushes a partial candidate on departure. Missing results no longer discard trustworthy participant rows. No official “all final fields finalized” event was verified.
- Cumulative reads and round rosters follow the native UI's indexing contract. Earlier-round leaver/substitute handling needs live validation. Missing entries not exposed in any round cannot be reconstructed.
- Additional scoreboard counters are documented but their relevance/reporting can vary by mode. API-supplied zero is preserved; missing calls/constants are unavailable. Mixed-mode objective totals are not synthesized.
- Categories describe an observed ability/effect, not a confirmed bar, equipment set or original class. Unknown effects are not inferred from names.
- Multi-team format support derives from the API, not hardcoded team counts. No new Update 51-specific format identifiers were invented. Actual queue availability and 4v4/6v6v6/9v9 behavior must be confirmed on the installed client.

## Release gate

The owner reports successful live testing of the tracking, observation functionality and 1.1 UI. The new 1.2 changes still need the [final refinement checklist](RELIABILITY_AUDIT.md). Offline Lua 5.1 mocks establish logic and syntax coverage only. Format-specific completed-match comparisons and multi-round disconnect/leaver cases remain useful before public distribution.

## Presentation-only additions in 1.1

`GetAbilityIcon(abilityId)` returns the exact ID's icon texture; nil/empty results produce a neutral placeholder. `GetClassIndexById(classId)` locates the index used by `GetClassInfo(index)`; its documented seventh return is the in-game keyboard icon, with the third (normal keyboard icon) as fallback. These lookups are guarded and cached in the UI, with no changes to the working tracking adapter.

Filters use the native `ZO_ComboBox` template and `ZO_ComboBox_ObjectFromContainer`, `ClearItems`, `CreateItemEntry`, `AddItem`, `SetSelectedItem`, `SetFont` and `SetSortsItems`. The source confirms that `SetSelectedItem` updates selected text without executing the item callback. Tables reuse `ZO_ScrollContainer` with independently sized `ScrollChild` controls. Native label alignment/wrap controls keep single-line values inside fixed columns; complete values remain in row tooltips.

## Native keybinding and display additions in 1.2

See [the audit](RELIABILITY_AUDIT.md) for source links and verified binding conventions. `GetActionIndicesFromName(actionName)` returns layer/category/action indices; `GetActionBindingInfo(layer, category, action, slot)` returns key plus four modifiers. Assignment text uses `GetMaxBindingsPerAction` and `GetKeyName`, guarded against missing/invalid information. `ZO_CreateStringId` defines the category/action labels before XML loads. No default or protected key assignment is attempted.

`GetUnitZone("player")` is a documented string-returning API. It is queried only while `IsActiveWorldBattleground()` and the current Battleground ID match the capture session. It supplies optional localized zone display text; original Battleground names/IDs stay preserved. It is not assumed to expose a more specific arena/ruleset name than the client actually provides.


## Unified live HUD additions in 2.0

The original tracker implementation was compared with the official [API 101051 documentation](https://raw.githubusercontent.com/esoui/esoui/live/ESOUIDocumentation.txt). `GetCurrentCharacterId()` scopes character-specific HUD records. `GetCurrencyAmount(CURT_ALLIANCE_POINTS, CURRENCY_LOCATION_CHARACTER)` provides the wallet baseline; `EVENT_ALLIANCE_POINT_UPDATE` supplies `alliancePoints, playSound, difference, reason, supplementaryInfo` after the event code. Verified earnings require a matching positive wallet change; initialization and personal/guild-bank currency reasons are excluded.

Competitive rank retains `ShouldShowLeaderboardForBattlegroundLeaderboardType`, `QueryBattlegroundLeaderboardData`, `GetBattlegroundLeaderboardLocalPlayerInfo`, `GetBattlegroundLeaderboardsSchedule` and `EVENT_BATTLEGROUND_LEADERBOARD_DATA_RECEIVED` from the working tracker. No new result-detection API is introduced. Native scene fragments, screen-resize/combat events and the ReloadUI prehook retain the original HUD behavior. Both native toggle actions share the verified existing binding architecture.

See [merge notes](MERGE_NOTES.md) for persistence boundaries, source architecture, the 104-test offline result and the merged release's outstanding in-game checklist. Original-addon gameplay testing does not constitute live verification of this integrated release.

## Rank refresh correction in 2.0.1

Rechecked the native [Battleground leaderboard](https://github.com/esoui/esoui/blob/live/esoui/ingame/leaderboards/battlegroundleaderboards_shared.lua) and [leaderboard list manager](https://github.com/esoui/esoui/blob/live/esoui/ingame/leaderboards/leaderboards_shared.lua). The native manager uses the same `QueryBattlegroundLeaderboardData` API, reads immediately only for `LEADERBOARD_DATA_READY`, and otherwise waits for the native data event. The native Battleground header accepts a positive `GetBattlegroundLeaderboardLocalPlayerInfo` rank without gating it on schedule readiness. No separate force-refresh API was verified; opening or manipulating native leaderboard selection is unnecessary and would affect the user's UI.

The HUD now preserves a labelled runtime cache during pending queries and retries absent/unusable replies within a bounded three-query cycle. A confirmed zero during a known active season establishes Unranked; loading/unavailable data is distinct. Query/response diagnostics remain debug-only. Eight new tests bring the suite to 112; live server timing still requires the owner's verification.

## Native editing and personal history in 2.1

The API 101051 documentation lists EditControl `SetSelectAllOnFocus`, `TakeFocus`, `LoseFocus`, `GetText`, `SetText` and `OnFocusGained`/`OnFocusLost`/`OnEnter`/`OnEscape` handlers. Numeric editors use these native methods without a per-keystroke settings callback. Label `GetFontHeight` supplies the shared card/heading layout. New history tables use the existing native scroll controls; no new game-event subscriptions or data-query APIs were introduced.

Character display delegates to the supplied ESO `zo_strformat(SI_UNIT_NAME, characterName)` convention; raw capture and stable keys remain unchanged. Personal owner IDs use the already verified `GetCurrentCharacterId` field on new snapshots. Older records rely only on their existing local-player flag/name, with ambiguous matches left unavailable. Damage taken and shields granted reuse existing verified scoreboard fields; blocked damage and mitigation are not inferred. See [the 2.1 notes](PERSONAL_HISTORY.md) for calculations, schema-compatible persistence and 142-test coverage.

## HUD location visibility in 2.1.1

Rechecked [official API 101051 documentation](https://raw.githubusercontent.com/esoui/esoui/live/ESOUIDocumentation.txt): `IsActiveWorldBattleground()` returns a boolean and `EVENT_PLAYER_ACTIVATED` supplies an `initial` boolean. Dossier's existing activation handler now refreshes the HUD's native scene-fragment preference reason before match processing, including the non-BG early-return path. Initialization and settings changes use the same visibility helper. No new listener, polling timer or match-state condition is added.

The optional character-specific `liveHUD.characters[key].preferences.visibilityMode` is `always` or `battlegroundsOnly`. Missing/invalid values default to `always`, preserving the existing `visible` master switch and other preferences. The SavedVariables versions/schemas remain unchanged. Effective visibility is the manual switch AND the permitted location, subject to native HUD scenes. Only fragment visibility changes; tracking is independent. Eight additional offline regressions bring the suite to 150; native loading-screen/scene behavior still needs in-game verification.

## Native keyboard configuration and UI stabilization: 2.1.2-rc1

The official [keyboard EditBox XML](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/editboxtemplates_keyboard.xml) shows the native `ZO_DefaultEdit` click handler calling `TakeFocus()`. The previous bare controls lacked this handler. Numeric and search inputs now inherit that template and explicitly enable documented `SetKeyboardEnabled`, `SetEditEnabled`, `SetCopyEnabled`, `SetPasteEnabled`, `SetSelectAllOnFocus`, `SetMultiLine` and `SetNewLineEnabled`. They keep native selection, cursor, key processing and paste behavior. Focus handlers use documented `HasFocus`/`LoseFocus`; no custom global keyboard callback is introduced.

API 101051 lists LabelControl `GetStringWidth` for font measurement and ButtonControl `GetLabelControl`, `SetEnabled`, `SetDisabledFontColor`, `SetNormalOffset` and `SetPressedOffset`. EditControl has no documented horizontal-alignment setter, so numerical text stays in a measured native editor centered in its value cell. A hidden label measures width only. No statistics or capture APIs change. Root `GetWidth`/`GetHeight` and the existing screen-resize event support rendered scale fitting without mutating the stored scale.

The [release-candidate notes](RELEASE_CANDIDATE_UI.md) document source evidence, remaining live gates and 169 passing offline scenarios. The mock simulates template focus and editing commands; it cannot verify the game's actual physical keyboard routing or rasterized layout.

## Button text-read correction: 2.1.2-rc2

Rechecked the official [API 101051 control documentation](https://raw.githubusercontent.com/esoui/esoui/live/ESOUIDocumentation.txt). ButtonControl supports `SetText` and `GetLabelControl` but does not expose `GetText`; LabelControl supports `GetText` and `GetStringWidth`. The rc1 line-60 hover failure was its unsupported `button:GetText()` call. The handler now reads/measures the returned label instead. There is no nil-check workaround, callback substitution or load-order change. Other runtime text reads target LabelControl or EditControl, and dropdowns continue using the native ComboBox interface.

The stricter mock rejects Button:GetText and exercises shared hover callbacks; three added tests bring the suite to 172. PLACE removal affects only the history column definitions/flexible width. Stored placement and all capture/result calculations are preserved. See the release-candidate notes for the exact rc2 in-game check.
