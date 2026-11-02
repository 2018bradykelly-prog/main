# ESCAPE THE CHAD

A Roblox multiplayer survival horror prototype. One randomly selected **OG Chad** hunts the survivors while they calibrate a suspicious machine for entirely fictional BP. All ranks and points reset each round.

## Play the prototype in Studio

1. Download/open `build/escape-the-chad.rbxlx` in Roblox Studio on Windows or macOS. The cloud build is already available. To recreate it from source, use the commands below.
2. In Studio's **Test** controls, choose **Server & Clients** (called **Local Server** in some versions), select **2 clients** or preferably **3**, and start the session. Regular solo Play deliberately waits for a second player.
3. After the 12-second intermission, exactly one player becomes OG Chad. Everyone else spawns as an LTN survivor. The map and HUD are generated when the server starts, so an empty editor viewport before Play is expected.

The HUD is compact by default. Click **Help** or press **H** for instructions, then **Close** to dismiss them. Click **X** on the status panel to hide it; the small **HUD** button brings it back. These buttons also support touch. New round messages and respawns do not reopen dismissed instructions.

4. As a survivor, hold **E** at the cyan **BP Calibrator** for 2 seconds. Each accepted calibration gives 25 BP; wait **6 seconds between completions per player**. Gamepad X and touch prompts also work.
5. Ranks are **LTN (0) → MTN (25) → HTN (50) → Chadlite (75) → Chad (100)**. The HUD, overhead labels, and player list display them. The team needs `max(4, survivors × 3)` calibrations to power the green exit. The terminal remains usable after the team goal so everyone can finish their personal rank.
6. At 100 BP, hold E at the green exit to escape once the team goal is complete. Escaped players wait safely in the lobby.
7. OG Chad runs slightly faster and captures survivors by approaching within 4.5 studs with clear line of sight. Captured survivors are moved to the cage. An ally can hold E at the exterior red rescue panel to release one teammate. Captives auto-release after 20 seconds, allowing 1v1 testing. New rounds and releases grant 5 seconds of capture immunity.
8. Rounds end when everyone remaining escapes, the four-minute timer expires, the killer disconnects, or all survivors leave. Results last 8 seconds, then roles and BP reset. Late joiners wait for the next round.

This version uses immediate contact capture; separate downed/carry states and Chad-versus-killer combat are future work. There is no monetization, persistent progression, or character roster.

## Original chase audio — one manual asset step

`assets/audio/chase-placeholder.wav` is an original synthesized eight-second loop, supplied with its deterministic Python generator. No third-party character or music IDs are used.

1. Publish a private test experience under the intended user/group in Studio.
2. Upload the WAV using Roblox's audio asset workflow in Creator Dashboard or Studio Asset Manager. Wait for processing/moderation, then grant the experience permission to use it where required.
3. Put its ID in `src/shared/Config.luau`: `ChaseSoundId = "rbxassetid://YOUR_NUMERIC_ID"`. Rebuild or sync before starting the test.
4. Approach OG Chad as a living survivor: music fades in inside 65 studs, reaching its configured maximum near 18 studs. It fades out when distant and stops on capture, escape, death, round end, or killer departure.

The shipped ID is empty: chase visuals work immediately, but **audio is silent until your upload is configured**. If playback fails, check Studio Output and asset ownership/experience permissions. Roblox cannot play a local WAV path as a SoundId. No API keys, HTTP requests, or DataStore settings are required for this prototype.

## Tooling and script sync

Pinned versions: **Rojo 7.7.1**, **Lune 0.11.1**, in `rokit.toml`. Install [Rokit](https://github.com/rojo-rbx/rokit) on your Studio computer, then run from this repository:

```sh
rokit install
rojo build default.project.json -o escape-the-chad.rbxlx
rojo serve default.project.json
```

Install the matching [Rojo Studio plugin](https://rojo.space/docs/v7/getting-started/installation/), open a local place, and connect the plugin to the local Rojo server (default port 34872). Accept the sync for this prototype place, then start a multiplayer test. Edit scripts in `src/`; Rojo syncs them into the DataModel. Restart the test after gameplay edits. Keep source-controlled scripts authoritative; Studio edits can be overwritten by sync.

Run Rojo **on the same computer as Studio**. The cloud machine's localhost is not your computer's localhost. You can download/copy this source project locally, or use the built place directly. No cloud port exposure is required.

### Studio MCP availability

This session exposed no Roblox/Studio MCP tools, and its runtime is Linux with no Studio process. A direct Studio connection was therefore unavailable. A built-in Studio MCP server on your computer is usable only when your AI client is configured to reach it; it is not automatically visible to this cloud session. This project uses the tested Rojo build path instead. No MCP connection or live Studio playtest is claimed.

## Development and checks

On this Linux cloud environment:

```sh
python3 tools/bootstrap.py
bash tools/check.sh
# Optional during editing; local clients only:
.tools/rojo serve default.project.json
```

The bootstrap downloads pinned official release archives with TLS verification and SHA256 checks. Tools live in ignored `.tools/`. The check script stops on the first failure and writes `build/escape-the-chad.rbxlx`.

On Windows/macOS after `rokit install`, create `build/`, then run:

```sh
rojo build default.project.json -o build/escape-the-chad.rbxlx
lune run tests/rules.spec.luau
lune run tests/place.spec.luau
lune run tests/world.spec.luau
lune run tests/hud.spec.luau
```

Verified in this cloud session:

- 22 rule scenarios, 251 assertions: unique killer assignment, rank thresholds, cooldowns, role restrictions, capture/rescue/immunity, auto-release, escapes, disconnects, timeouts, reset, chase-distance curve.
- Compilation of all 7 source files and 28 checks against the built place hierarchy/source contents.
- Actual map creation using Lune's Roblox instance model: 98 checks, spawn clearance, sealed cage, interaction-ray clearance, and connected walking routes to interactions.
- Live Rojo server handshake and project snapshot retrieval: 17 instances served successfully.
- HUD construction, compact sizing, help dismissal, hiding/restoring and viewport checks using the actual HUD module. This does not simulate Studio input or rendering.
- Original WAV generated, checked for valid format/nonzero signal, and reproduced deterministically.

These are automated code/build/map tests. They do **not** run Roblox networking, physics, UI rendering, prompt signal delivery, character spawning, or audio playback. Complete the Studio checklist before calling the prototype playtested. CI runs the same automated tests and uploads the place; CI itself has not yet run remotely.

## Studio acceptance checklist

- [ ] Start 3 clients; server and client Output contain no errors. One killer, two survivors; all begin with correct roles/score.
- [ ] Complete terminal holds from both sides. A short/canceled hold, killer use, distant use, or repeat inside the cooldown gives no BP. Both survivors can progress independently.
- [ ] Observe every rank threshold in HUD, overhead labels and player list. Team power alone cannot let an LTN escape; Chad alone cannot escape an unpowered exit.
- [ ] Run killer toward survivor: chase cue appears; after audio upload, sound fades by distance. Capture works in open space, not through walls.
- [ ] Capture a survivor, rescue with the other, verify immediate release and 5-second immunity. Capture again and wait 20 seconds for automatic release.
- [ ] Reset characters while alive/captured. Score persists within the round; resetting while captured does not bypass the cage.
- [ ] Escape both survivors, then test a timeout. Results and subsequent round reset correctly. Repeat with 2 players to verify automatic release prevents a cage deadlock.
- [ ] Add a client during an active round: lobby until the next round. Disconnect the killer and then test survivor departure in a new round.
- [ ] Check HUD at a narrow/mobile viewport and verify touch/gamepad prompt input.

## Layout

```text
src/shared/Config.luau         Tuning, ranks, audio asset configuration
src/shared/Rules.luau          Pure rank/chase/objective calculations
src/shared/RoundState.luau     Pure server-owned round state machine
src/server/Main.server.luau    Multiplayer lifecycle, validated interactions
src/server/World.luau          Generated map, prompts, lighting and spawns
src/client/Main.client.luau    HUD, rank labels, local chase audio
src/client/Hud.luau            Compact status and dismissible instructions
tests/                        Rule, build and map validation
assets/audio/                 Original WAV and audio notes
tools/                        Bootstrap, check runner and audio generator
```

Clients never award BP or select roles. The server checks character health, distance, line of sight, hold timing, phase, role and cooldown before accepting interactions. Movement anti-cheat and production-scale balancing are outside this prototype. Use the existing checkout in cloud tasks; a separate Git worktree is unnecessary.
