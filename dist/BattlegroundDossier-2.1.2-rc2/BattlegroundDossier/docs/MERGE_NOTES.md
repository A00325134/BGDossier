# Unified Battleground Dossier 2.0.0

## Rank refresh correction in 2.0.1

The owner reported that rank became Unranked after a match until the native leaderboard was opened. Inspection found that every query erased the known rank before checking whether its asynchronous response was ready, and unanswered queries had no timeout/retry. In addition, the HUD rejected positive ranks when schedule metadata was unavailable, although the native UI accepts positive local rank directly.

The patch retains a runtime rank with a **BG RANK (cached)** label during refresh, displays **Loading...** without a confirmed rank, and makes at most three queries one minute apart if no usable answer arrives. It displays **Unavailable** after timeout; a confirmed zero rank in an active season remains **Unranked**. Successful or late matching native data events update the rank without opening the leaderboard. Old timers are cancelled on initialization, successful replies and unavailable leaderboard selection. Rank still expires with the season and is never persisted. AP, match capture and SavedVariables schema are unchanged.

The current suite passes **112 tests**, including eight new asynchronous rank regressions. This patch needs an in-game check: finish a match without opening leaderboards, watch cached/loading transition to the received rank, and compare with the native board afterward. Enable `/bgd debug on` for query state and response diagnostics if the server still does not supply data. Neither tests nor the patch can force the server to publish a rank.

Install only `AddOns/BattlegroundDossier/`. Disable the old BGSessionTracker addon in ESO to avoid duplicate overlays and command conflicts. The project's `tracker/` directory remains an unchanged reference and is excluded from the install ZIP. No external libraries are required.

## Architecture reviewed

| System | Dossier | Original tracker |
| --- | --- | --- |
| Manifest | `BattlegroundDossier.txt`, API 101051 | `tracker/BGSessionTracker.txt`, API 101051 |
| Namespace | `BattlegroundDossier` | `BGSessionTracker` |
| Initialization | Root `BattlegroundDossier.lua`, addon-loaded callback | `tracker/BGSessionTracker.lua`, separate addon-loaded callback |
| Persistence | Account-wide `BattlegroundDossierSavedVariables`, schema/version 1 | Character-specific `BGSessionTrackerSavedVariables`, version 1, world namespace |
| Match results | `MatchTracker.lua` final scoreboard verification and `Storage.lua` staged commit | `Tracking.lua` separate state/result retries and eligibility latch |
| Other events | Activation, scoreboard, attributed combat | AP, Competitive leaderboard, HUD combat/screen resizing |
| Commands | `/bgd` and subcommands | `/bgtracker`, `/bglock`, `/bgstats`, `/bgreset` |
| UI | Full analysis window and native binding | Compact scene-fragment HUD with drag preferences |

Both manifests and all original tracker files were inspected before integration. The legacy initializer and match-result detector are not loaded. `LiveSessionCore.lua` retains its utility calculations, `LiveSessionHUD.lua` retains its visual/drag/scene implementation with adapted namespace/window names, and `LiveSession.lua` integrates session persistence, commands, AP and rank subscriptions. The merged runtime uses only the Dossier namespace and one addon-loaded owner. No legacy global or SavedVariables declaration is required.

## Shared results and preserved calculations

Dossier tags an actively observed pre-completion match with the current character's live-session token. Its existing FINISHED-only capture collects and verifies the scoreboard. Intermediate rounds never commit results. `Storage:Commit` checks the existing match ID, stages encounter/lifetime updates and the HUD result, then publishes them together. A derivation error cannot partly increment history or session counters. HUD refresh and a throttled rank request follow publication.

The HUD has no separate Battleground state/scoreboard subscriptions or result retry timer. Existing Dossier handlers supply eligibility and activation rank refresh. Duplicate completion/scoreboard events cannot increment either system again. Results appear after the existing verification window, normally 30 seconds, rather than the legacy tracker's independent earlier read. No trustworthy scoreboard means no saved match or HUD result.

Full, understaffed, uneven and three-team support comes from the actual Dossier roster. The original HUD win percentage remains **wins / (wins + losses)**, excluding draws. Draws remain separately retained and included in its completed count. Unresolved results are explicit in `/bgstats`, never invented as losses. Dossier lifetime percentages retain their existing denominator. A match must have been observed before FINISHED in the current live session to contribute to that session.

Original AP verification excludes initialization and personal/guild-bank transfers, ignores duplicate events and rebases on spending without subtracting earned AP. Inconsistent updates are skipped. Original Competitive-only selection, one-minute query throttle, native data callback, season expiry and Unranked handling remain. Rank is not persisted across UI loads. Both systems operate with the main analysis window closed and the HUD hidden.

## Data compatibility

The sole manifest SavedVariables declaration remains `BattlegroundDossierSavedVariables`; the ESO version and main schema remain **1**. Existing histories, profiles, observations, settings and main native keybinding remain compatible. New local-character/session snapshot annotations are optional.

The additive `liveHUD = { version = 1, characters = ... }` subtree independently versions preferences, sequence and current session. Keys use world and character ID. Up to 128 character records are stored; overflow characters receive a usable temporary HUD and explicit persistence warning without evicting records. Unsupported future HUD versions are preserved and disable only the HUD, leaving Dossier available.

Login/character change starts a new live session. A deliberate ReloadUI hook creates a one-use marker; only reloads within 120 seconds resume the session. Wallet AP is rebased on reload/reset: gains during downtime are not inferred. Old pending candidates can still save Dossier history but cannot credit a new character/session's HUD. Resetting while a current candidate is pending keeps that result eligible; resetting after a save cannot recount it.

**No automatic legacy migration is claimed or attempted.** ESO does not reliably expose a disabled/uninstalled addon's separate SavedVariables file. The old `BGSessionTrackerSavedVariables.lua` is neither declared nor accessed and remains untouched. Configure HUD preferences once in Dossier; a new session starts normally. Do not copy the old file over Dossier's file. Back up both files with ESO closed before upgrading. The old addon need not stay installed or enabled.

`/bgreset` and the HUD settings reset require confirmation within 15 seconds, preserving history and preferences. `/bgd reset` retains its separate 30-second destructive-history confirmation and leaves live counters intact. Pruning match detail does not affect live counters or lifetime player totals.

## Controls and packaging

The existing Settings page adds **LIVE SESSION HUD** controls for visibility, locking, independent scale, opacity, header, position reset and protected session reset. Original HUD dimensions, colors, fonts, native scene behavior and drag interaction are retained. Clicking the HUD does not open another window.

Open **ESO Settings → Controls → Keybindings → Battleground Dossier** and assign **Toggle Battleground Dossier** and optionally **Toggle Live Session HUD**. Both use one `Bindings.xml`, with no forced defaults. `/bgd` toggles analysis, `/bgtracker` toggles the HUD, `/bglock` controls dragging, `/bgstats` prints diagnostics and `/bgreset` requires confirmation. Original tracker command variants remain; see README.

The release contains one manifest, eighteen Lua files, one Bindings.xml and documentation. Reference sources, tests and Rider files are excluded. Packaging checks the archive for duplicate manifests/binding files and compares every shipped file with source.

## Verification and remaining limits

**104 offline Lua 5.1 tests pass:** 81 existing regression cases plus 23 merge cases. Added coverage includes four roster formats/understaffed 3v3, duplicates, W/L/draw/unresolved calculations, AP spending/duplicates/all excluded reasons, rank throttle/expiry/unranked, independent windows/bindings, HUD geometry/preferences, protected resets, pending-result resets, reload expiry, per-character isolation, old pending results after login/character changes, transactional rollback, future HUD versions and single event ownership.

Both original addons were tested by the owner in ESO. **The merged build still requires in-game testing.** Mocks cannot certify rendering or native event timing. Existing limits remain: no permanent server match ID, incomplete client-visible observations, and no guarantee all final fields arrive before departure. Missing outcomes stay unresolved. AP during downtime cannot be reconstructed; Competitive rank requires server availability and current data.

## In-game acceptance checklist

- With ESO closed, back up SavedVariables. Install the unified folder, disable the legacy tracker and confirm one HUD, one addon and no Lua errors.
- Open existing matches, player dossiers, observations and lifetime statistics. Compare with pre-upgrade totals; verify `/bgd` and its existing binding.
- Assign both native bindings; toggle the two interfaces independently. Unlock/drag/relock the HUD; adjust scale, opacity and header; reset position. Check normal combat input, native scenes and settings scrolling at your resolution.
- Earn AP with the main window closed, then spend/bank AP. Verify only positive verified earnings count. Compare Competitive rank with the native leaderboard and check an unranked character.
- Complete available full/understaffed/two-/three-team and multi-round matches. Confirm one saved scoreboard and one session result after verification, no interim-round increment, correct profiles and preserved combat observations. Reopen the final scoreboard repeatedly without duplicate results.
- Reload during a round and final capture; confirm one result and session resume within 120 seconds without outage AP. Log out/change characters: verify fresh sessions and retained history/per-character preferences.
- Exercise reset cancellation, timeout and confirmation before/after completion. Confirm session reset leaves history intact and a saved result cannot return. Retain the existing [UI](UI_ACCEPTANCE.md) and [reliability](RELIABILITY_AUDIT.md) checklists for broader regression testing.
