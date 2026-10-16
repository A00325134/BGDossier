# Battleground Dossier

An independent Elder Scrolls Online addon for saved Battleground scoreboards, player encounters, comparisons and observed combat abilities. No libraries, companion software, network access or BGSessionTracker dependency are needed in game.

Version **1.2.0** targets **ESO API 101051 (Update 51)**. The project owner has confirmed the tracking systems and 1.1 UI working in ESO. This final pass adds native keybindings and targeted data-reliability corrections while preserving that interface. **The new 1.2 changes have not been live-tested by the developer.** See [the reliability audit and final in-game checklist](docs/RELIABILITY_AUDIT.md).

Existing matches, encounter histories, ability IDs and observations remain compatible. SavedVariables schema stays at **1**. New participant IDs/confidence, completeness diagnostics, final-team counts and localized zone names are optional annotations on new captures. Old records are read without inventing these fields. There is no destructive migration, history reset or dependency change. `CombatTracker.lua` remains unchanged; the collection/storage fixes are described in the audit.

## Installation

1. Extract the release ZIP into `Documents\Elder Scrolls Online\live\AddOns\`. The result must be `AddOns\BattlegroundDossier\BattlegroundDossier.txt`, with the Lua files beside it. Documents may be redirected to OneDrive on some systems.
2. Alternatively, copy this project's manifest, all fifteen manifest-listed Lua files and `Bindings.xml` into an addon folder named **BattlegroundDossier**, using that exact name. Do not copy the project as a nested `BGDossier\BattlegroundDossier` folder. When updating an existing installation, replace the addon files and leave the separate SavedVariables file in place.
3. Restart ESO or return to character selection. Enable **Battleground Dossier** in Add-Ons. On a newer client API, check the compatibility notes before allowing an out-of-date addon.
4. Enter a character and type `/bgd`. No dependencies need enabling.

ESO writes `SavedVariables\BattlegroundDossierSavedVariables.lua` when logging out or reloading the UI. Account-wide settings, histories and statistics are shared by your characters; player identity keys include the megaserver. Every saved match identifies the participating local character. As with other addons, a client crash before ESO writes SavedVariables can lose the current session's changes.

## Using the interface

`MATCHES` opens compact history rows with result colour, map, mode, date, format, personal K/D/A, damage and team placement. Search players/accounts and combine independent **Result**, **Game mode** and **Format** dropdowns. **Clear filters** clears the search and all active filters. Select any row for its saved scoreboard. **Back** restores history search, page and scroll position.

The scoreboard uses fixed column widths, alternating rows, hover highlighting, team stripes and a separately scrolling roster with fixed headers. Numerical headings sort in either direction; **—** values sort last. **★** marks you and **◆** identifies a previous encounter. The team dropdown supports allies, opponents, familiar players and individual teams. Values use grouped thousands and optional K/M abbreviations; hover a row for exact statistics and full identity. Your selected row stays highlighted after returning from its dossier.

Click anywhere on a player row to open a contextual dossier inside the main window. Its tabs separate **Overview**, **Observed abilities**, **History** and **Scoreboard details**. The overview has compact stat cards and team averages/shares. History retains lifetime encounters, known aliases/classes, team results, record totals and links to older scoreboards; details retains all additional counters, medals and lives information. **Back** returns to the roster without closing the window.

Choose **Select as A** / **Select as B** in two dossiers, then **Compare A / B** (or use **Compare with me**). Comparison has side-by-side names/classes, values and A-minus-B differences, with controls to change participants, swap sides and inspect either player's observed abilities. No overall winner is assigned. K/D is unavailable for zero deaths rather than being presented as infinity.

`PLAYERS` searches account names and retained character aliases. The database table shows observed classes, encounters, allies/opponents, team record and familiarity badges. Select a row to open its lifetime dossier. The abilities tab separates **Lifetime** observations from the **Latest match** still retained. An older match's “previous encounters” marker remains frozen, while lifetime totals can include later matches.

`STATISTICS` uses cards for lifetime W/L/D totals, win percentage, stored player identities and familiar opponents, followed by personal records, frequent-player tables and recent averages. Known identities count stored account/character profiles, not a claim that character-only profiles belong to different accounts. Familiar opponents means profiles encountered as opponents at least twice. Trends compare up to ten recent retained matches with the preceding ten, show available sample counts in tooltips, and leave unavailable comparisons blank.

`SETTINGS` groups **Appearance**, **Keybindings**, **Behaviour**, **Data & retention**, and **Debugging**. Existing options remain connected: scale/position, automatic opening, notifications, combat recording, debug messages, storage limits and recognition thresholds. Presentation preferences control compact numbers, ability icons and the default section after login/reload. Storage cards show retained records, profiles and ability summaries. History reset requires arming and confirmation within 30 seconds, with a Cancel option; the protected slash commands also remain available.

Drag the window to reposition it. Close with **×**, Escape or `/bgd`. It hides on entering combat, and automatic opening is suppressed while combat persists. Native scrollbars navigate long tables; history/player databases use pages of 40, and very long ability aggregates use pages of 80 without discarding recorded IDs. Search is debounced. Controls are reused between renders; a lightweight check refreshes saved-data views only while the window is visible and outside combat.

The Format dropdown includes recorded team-capacity formats (such as 6v6v6), Competitive (authoritative MMR-impact flag) and Big Team Battles (reported team capacity at least six). Recorded participant counts remain separate from capacity. “Competitive” is not inferred solely from a four-player team size.

## Commands

| Command | Action |
| --- | --- |
| `/bgd` | Toggle window |
| `/bgd last` | Latest saved match |
| `/bgd history` | Match history |
| `/bgd players` | Player database |
| `/bgd stats` | Statistics |
| `/bgd settings` | Settings |
| `/bgd help` | Command help |
| `/bgd debug on` / `/bgd debug off` | Lifecycle diagnostics |
| `/bgd reset` | Arm destructive history reset for 30 seconds |
| `/bgd reset confirm` | Confirm armed reset; settings are retained |

Only `/bgd` is registered. BGSessionTracker files and commands are untouched.

## Native keybinding

Open **Settings → Controls → Keybindings → Battleground Dossier** and assign **Toggle Battleground Dossier**. ESO manages supported keys, modifiers and conflict warnings. No default key is assigned, and the addon never captures or changes other bindings. The action uses the same toggle as `/bgd`, so it opens and closes the existing window.

The addon's **Settings → Keybindings** section displays the native assignment when all required API information is available; otherwise it shows navigation instructions. There is no speculative menu-opening button or custom key recorder. Native action/localization strings load before `Bindings.xml`; assigned keys are saved by ESO, not duplicated in addon SavedVariables.

## How match recording works

The tracker starts or resumes a session on Battleground activation/state changes. `BATTLEGROUND_STATE_FINISHED` is the only capture trigger. `POSTROUND` does **not** finish a match. Combat recording pauses between rounds. A match's ID is a local session token (world, timestamp and saved sequence), not a claimed server match ID. The token and capture marker survive `/reloadui`; saved IDs are checked before encounter/statistic aggregation.

At completion, the addon listens to scoreboard updates and reads once a second for a **30-second verification window**, rather than committing after only three seconds. This intentionally delays automatic opening to give late participants/results time to arrive. Every exposed scoreboard slot is captured, including zero-stat players, character-only identities and unnamed slots. No damage, kill, assist, account-name, observation or historical-profile threshold is required. A completely empty roster cannot be saved.

The latest candidate is retained under the active session, along with earlier reliably identified participants who disappear from a subsequent read. Missing fields remain unavailable; known numeric values from an earlier read can be retained with an explicit provenance/partial marker, while numeric corrections from later reads replace earlier values. On leaving, UI deactivation or scoreboard clearing, a nonempty candidate is flushed once and marked **Partial** if verification ended early. Reload can resume a persisted candidate and its remaining deadline. Profiles, match history and lifetime totals are published together after derivation succeeds; a derivation error does not partly increment encounter totals.

Missing team/results/local identity information no longer rejects the whole match: trustworthy participant data is saved with unresolved fields and a completeness notice. Unknown teams are neutral, never automatically enemies. Colliding identities remain separate unresolved match rows and do not create permanent profiles or receive attributed combat abilities. A snapshot is still limited to information ESO exposes; the verification window is not a guarantee of server finality.

For multi-round Battlegrounds, it enumerates round rosters and uses the native cumulative-statistics API with each participant's most recent round/index. This retains earlier-round leavers where those round entries remain available. Team aggregate scores are **rounds won**; per-round team scores are saved separately. Mixed-round objective totals are unavailable because different modes use different units. Single-round objective columns mirror the native UI: damage taken for Deathmatch, ball-carry seconds for Murderball, captures for the other verified objective modes. The detailed dossier also shows the other exposed scoreboard counters.

Team results use `GetBattlegroundResultForTeam`, including true ties. Placement is competition rank by final score/round wins, shared by tied scores; it is not a fabricated official placement field. Three-team results against another player count a win only when your team won and their team lost, a loss only in the reverse case, and a draw only when both teams have authoritative ties. Two losing teams have an **unresolved** result against each other.

A candidate with unsettled or incomplete fields is saved with a partial notice when the window ends. If no final entries ever become available, a chat message explains that no record was saved. Leaving **before FINISHED** still does not create a completed match. Session identity is reused across reloads, checked against saved IDs before aggregation, and expired after six hours; entering a different session flushes an existing completed candidate first. Rejoining after actually leaving can start a new observation session because no permanent server match ID is exposed.

Capacity is distinct from participation: a Competitive 4v4 with six entries remains a valid six-participant match and displays **Competitive 4v4 • Final roster 3v3**. Uneven sizes and three-team formats are derived from exposed team assignments. Final-roster sizes do not claim historical concurrent team sizes when substitutes/leavers were present; total retained participants can exceed the latest round's roster count.

Enable `/bgd debug on` for one save-time summary of exposed final-round entries, captured rows, saved participants and account/character-only/unresolved identity counts, plus mismatch/partial warnings. Debug mode also exposes these counts in a saved scoreboard. Normal gameplay does not receive these diagnostics.

New captures prefer the localized `GetUnitZone("player")` name while still inside the matching Battleground. The original `GetBattlegroundName` value and Battleground ID remain saved; history tooltips retain the original name. If no valid localized zone is available, the exact original name is displayed. No map-name string stripping or guessed renaming is applied, and older records are not retroactively renamed.

## Player recognition

Account display names (`@name`) are preferred, normalized and scoped to the megaserver. Different characters merge only when their scoreboard explicitly reports the same account. Without an account, the exact normalized character name forms a limited-confidence profile. Only grammatical suffixes, color markup and surrounding whitespace are stripped; there is no fuzzy name matching. Within one match, an exact unique character can be associated with an account explicitly reported for that character in another round/read, preventing duplicate participation when names arrive late. Previously saved character-only profiles are **not** merged into account profiles. Account renames cannot be reliably linked; recycled character names can affect character-only history. Entirely unresolved/ambiguous participants remain accessible in the match roster without creating misleading permanent profiles.

The default frequent-player threshold is five encounters in the relevant relationship. Labels describe encounter frequency, never skill. An optional one-time match-start chat notice counts reliably identified profiles from the available scoreboard. It can miss players whose identity arrives late; it does not query hidden enemy identities. Your own local entry is excluded from the familiar-player database.

## What observed abilities mean

Only supported damage/healing combat results visible to your local client are summarized. Source names must match exactly one current roster identity. Pet/companion, unknown, ambiguous and error sources are discarded. Unit IDs from combat events are **not** treated as account identities. Name caches are reset on roster changes. Events arriving before the roster identifies a source are discarded rather than retroactively guessed.

An ability record contains its ID, supplied name, first/last observed timestamps, relevant event count and observed damage/healing values when available. **Event counts are not cast counts.** Damage-over-time and healing-over-time ticks count as events. Healing values are observed event values, not a claim of effective healing after overheal. Client-known progression metadata may identify class, weapon or guild/world categories; unknown tick/proc IDs remain “Other observed effects.” Subclassed abilities do not establish a player's original class or complete build.

Observed abilities use a fixed-height table: **Ability | Category | Events | Damage | Healing**. Sort any heading; damage is the initial sort where available, otherwise healing or event count. IDs, exact numbers and first/last timestamps are in row tooltips. Icons come from `GetAbilityIcon` for the exact recorded ID, with neutral placeholders when unavailable. Saved categories are shortened for display, never guessed from ability names. Identical names with different IDs remain separate rows.

The match dossier separates **This match** from **Previous matches**. The latter aggregates all distinct IDs available in earlier retained matches and pages large lists without dropping entries. The player database's original bounded lifetime ability summary also includes observations from pruned matches. Old observations do not establish what is currently equipped. Combat visibility, distance and game restrictions mean many opponent abilities/heals will never be observed. There is no full equipment, traits, enchantments, Champion Point, skill bar, private-statistic or hidden-MMR inspection.

## Storage and maintenance

Defaults: **200 detailed matches**, **10,000 lifetime profiles**, **80 distinct abilities per match participant and lifetime profile**, **24 character aliases per profile**, and **200 retained match references per profile**. History can be set to 10–1000 matches, profiles to 100–20,000. Each active match bounds observation owners at 100 and unmatched-name cache entries at 256. Final capture uses one persisted candidate, a 100-entry sanity budget per queried round, up to twenty earlier round rosters plus the current round, and a 2,100-row budget for retaining earlier reads. Current exposed final-round rows are never truncated to the advertised format. Unusual budget truncation is marked partial. Only summaries are saved, never raw combat events.

Pruning removes old match detail and dangling links, while retaining lifetime encounter/statistic totals and bounded historical abilities. Existing profiles continue updating at the profile limit; new profiles are skipped and the saved scoreboard displays a notice. Reaching an ability limit skips new distinct ability IDs, while already tracked abilities continue aggregating. Lowering the profile limit does not delete existing profiles. Maximum-stat links may refer to a pruned match; the recorded value/date remain. Back up SavedVariables before updates or resets.

Storage schema is separate from ESO's SavedVariables version, which remains fixed at 1 to prevent ESO replacing history on addon updates. Missing known fields are initialized; unrecognized records are retained and omitted from views if structurally invalid. A newer unsupported schema disables initialization rather than overwriting it. No update silently resets all history.

## API verification and known limits

See [docs/API_VERIFICATION.md](docs/API_VERIFICATION.md) for signatures, primary sources, fallbacks and release gates. API 101051 is verified from the repository's current `live` documentation; availability on your installed server/client must be checked in game. Format support is dynamic and has **not** been live-certified for 4v4, 6v6v6 or 9v9.

Known unverified behavior includes cumulative-statistic results for a player who departed an earlier round, the exact delay of final scoreboard updates, complete round-roster retention after reconnection, native font/layout clipping at different resolutions, and how much enemy combat information the client exposes. Scoreboard APIs can return numeric zero for an unsupported/mode-irrelevant counter; the addon cannot distinguish such an API-supplied zero from a genuine zero. It stores nil only when a call/constant/value is absent or invalid. Captured scoreboard damage/healing and observed event damage/healing are intentionally separate.

## Validation

Offline tests run under **Lua 5.1**, with mocked ESO APIs and UI controls:

```powershell
uv pip install lupa
python tests/run.py
```

The test runner explicitly imports `lupa.lua51`. **81 offline scenarios pass** (33 core, 22 UI and 26 reliability/keybinding cases), and all fifteen manifest-listed Lua files compile and load. XML structure, native binding action, manifest order and absence of a forced default binding are also checked. Reliability cases include all requested full/understaffed formats, zero statistics, missing accounts/names/teams, similar names, leavers/substitutes, late updates, repeated completion, reload/deactivation, account resolution, rollback on derivation error, existing schema-one history and final statistical corrections. Native drawing and live engine semantics are not mocked faithfully enough to certify gameplay behavior.

In-game acceptance checklist:

- Enable with empty SavedVariables; check `/bgd`, every tab, search, Escape, dragging, scaling, scrollbar, tooltips and all slash commands without Lua errors.
- Complete each available 4v4, 6v6v6 and 9v9 format; compare every captured player/team statistic with the native final scoreboard. Verify team IDs, mode names, objective units, medals, ties and unequal teams.
- Complete a multi-round match. Confirm no save at intermediate `POSTROUND`, one final record, cumulative totals and separate round scores. Test an earlier-round leaver and substitute.
- Observe delayed updates with debug enabled. Confirm no empty/preliminary save, no duplicate on repeated scoreboard updates or `/reloadui`, and useful timeout diagnostics.
- Reload during a round and at the final scoreboard; change local character after a match; disconnect/reconnect; leave early; verify preserved history outside Battlegrounds. Confirm the active match token is reused only while appropriate.
- Encounter known accounts on different characters; verify ally/opponent totals and team results. Exercise missing-account and ambiguous-name cases without merges.
- Check observations against visible combat activity. Confirm ticks increment event counts, pet sources are ignored, missing observations show the empty state and old abilities are clearly historical.
- Compare players with zero deaths and unavailable stats. Test history filters and long/localized names at the lowest supported scale.
- Set a low match limit; verify pruned links and retained lifetime totals. Back up SavedVariables, then test the reset timeout/confirmation.

Build the distributable with `python tools/package.py`. It includes only the addon, README and API notes, under the required addon folder name.
