# DEEP HAUL

A Roblox deep-sea salvage game. Pilot a submarine down through six ocean zones, catch fish with a
quick timing minigame, salvage sunken treasure with your claw, and surface before your oxygen or
hull gives out. Sell your haul, upgrade your sub, fill your Index and aquarium, and Resurface
(rebirth) to open The Rift.

Everything (the world, the models and all the UI) is built from code: there are no uploaded
assets. The project syncs into Studio with [Rojo](https://rojo.space).

- `PLAN.md`: architecture, module map and build phases
- `BALANCING.md`: pacing targets, loot maths and economy simulation results
- `SOUNDS.md`: every sound slot and how to fill it

## Getting started

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (Rojo 7.4.4, selene, luau-lsp).
2. Build a place file with `rojo build default.project.json -o DeepHaul.rbxl`, or run `rojo serve` and connect from the Rojo Studio plugin.
3. In Studio, go to **Game Settings → Security** and enable **Studio Access to API Services**, so saving, leaderboards and badges work while testing. Without it the game still runs: saves use ProfileStore's mock store, and the leaderboards show the current server.
4. Press Play. New players get the tutorial; press **F8** (Studio only) for the debug console.

Before publishing:

- **Max Players:** set it to **12** or fewer in Game Settings. There are 12 aquarium plots (`Game.Aquarium.Plots`).
- **Monetization:** create the passes and products and paste their IDs into `src/shared/Config/Products.luau`. An ID of 0 shows as "Coming soon" and is never prompted.
- **Badges (optional):** create them in the Creator Dashboard and paste the IDs into `src/shared/Config/Badges.luau`.
- **Sounds:** see `SOUNDS.md`.
- **Codes:** edit `src/server/Config/Codes.luau` (players redeem them in Shop → Codes). It lives on the server only, so players can't read it.

## Controls

| Action | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| Steer | WASD + mouse | Left + right stick | Joystick + drag |
| Rise / sink | Space / Shift | R2 / L2 | ▲ UP / ▼ DOWN |
| Catch / salvage | Click / hold click | A / hold A | ACTION / hold |
| Thrusters (burns extra oxygen) | Hold Q | Hold RB | Hold 🚀 BOOST |
| Sonar | F | Y | 📡 SONAR |
| Silent running | Ctrl or C | L3 | 🤫 SLOW |
| Emergency surface | Hold R | Hold X | Hold 🚨 |
| Free the cursor | Alt | | |
| Menus | M | Select | Side bar |
| Dock interact | E | X | Tap the prompt |

## Game systems

- **Core loop:** launch from the pier and dive. Catch fish (≤3 s timing bar; rarer fish have a smaller zone and a faster marker, and landing the marker dead centre is a PERFECT catch). Salvage treasure (hold, needs the right claw tier), then surface to secure your cargo. Sell at the Fish Market and upgrade at the Workshop.
- **Zones:** Sunlit Shallows, Twilight Reef, Midnight Zone, Abyssal Plains, Hadal Trench, and The Rift (after your first rebirth).
- **Hazards:**
  - Oxygen drains as you dive, and hull pressure damages you below your rated depth.
  - Predators hunt you; sonar stuns them and silent running sneaks past.
  - Darkness below the Twilight Reef limits you to your floodlights.
  - A blackout loses half your cargo unless you're insured.
- **Catch streaks:** catching or salvaging within 15 s of your last find adds +5% value per step (up to +50%) until you surface.
- **Loot:** 78 fish and 68 treasures across 8 rarities with exact odds. There are 7 mutations, plus weight, Colossal catches (1 in 500, ×5 value, 3× size) and 5 treasure conditions. Treasure falls into 6 categories and 13 collection sets.
- **Progression:**
  - 8 upgrades with 15 levels each; Resurface (rebirth) gives a permanent sell multiplier, tokens for a perk shop, and The Rift.
  - The Index shows silhouettes, completion, your exact odds and milestone rewards.
  - The personal aquarium earns passive coins, plus offline earnings capped at 8 hours with a "Welcome back" popup.
- **Retention:** daily streak calendar, 3 daily and 3 weekly quests, 24 achievements (with sub skins), global leaderboards on the dock, and codes.
- **Events:**
  - Automated and seeded from UTC, so every server matches: every 45 minutes for 10 minutes, with a 60 s countdown.
  - 6 events, each with exclusives: Bloom, Leviathan Migration, Sunken Galleon, Golden Tide, Deep Tremor and Blood Moon.
  - 5% chance of a Super Event, plus Weekend Luck.
- **Big catches:** Mythic and rarer get a flash, shake, slow motion and a server announcement. Secrets are announced in every server (MessagingService).
- **Monetization:**
  - Game passes, developer products and coin packs.
  - Purchase handling can't grant twice and only confirms after the purchase is saved.
  - A PolicyService check covers the one random item (with exact odds shown).
  - Nothing sells fish or treasure.

## Project layout

```
default.project.json   Rojo mapping (see PLAN.md)
src/first/             ReplicatedFirst: loading screen
src/shared/            ReplicatedStorage.Shared
  Config/              ALL game data and tuning (fish, treasure, zones, upgrades, events, ...)
  Modules/             pure shared logic (loot maths, stats, event schedule, fish paths, ...)
  Models/              procedural fish / treasure / submarine builders
src/server/            ServerScriptService.Server (authoritative)
  Main.server.luau     service bootstrap (ORDER list)
  Services/            one service per system
  Pure/                server-only pure logic (data schema, loot pools), unit tested
  World/               procedural terrain, decor, dock, event models
  Config/Codes.luau    redeemable codes (server-only)
  Vendor/ProfileStore  session-locked saving (Apache-2.0)
src/client/            StarterPlayerScripts.Client
  Main.client.luau     controller bootstrap (ORDER list)
  Controllers/         input, sub, HUD, effects, rendering, menus, tutorial, events, ...
  Menus/               Inventory, Index, Upgrades, Shop (+ Codes), Quests, Launch panel
  UI/                  UI kit, windows, sliders, item cards and 3D viewports
tests/                 unit tests for pure modules (luau CLI)
tools/                 check.sh, test bundler, economy simulator
```

## Security model

- **The server is authoritative.** Clients only send intents. Every remote is rate-limited (a token bucket per player per remote) and validated for types, ranges and ids, and the server re-checks distance, cooldowns, claw tier and cargo space.
- **Sub movement is client-owned for responsiveness.** The server validates speed, teleports, world bounds and the Rift seal, and snaps back or ends the dive on repeated strikes.
- **Loot is rolled only on the server.** Catch timing is checked against the server's own session and marker formula.
- **Codes live only on the server,** with a lockout after repeated wrong guesses.

## Verification

```
tools/check.sh          # strict luau-lsp type check, selene, unit tests, rojo build
python3 tools/bundle_tests.py --script tools/economy_sim.luau && luau build/script_bundle.luau
```

The unit tests cover the loot maths, rarity odds, event schedule, stats and upgrade costs, the
data schema and migrations, loot pools, fish paths, the Leviathan path, quests and the login
calendar.
