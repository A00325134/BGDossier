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
