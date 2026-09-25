# DEEP HAUL — Build Plan

This file is the architecture and build order for DEEP HAUL. It is kept up to date as phases finish.

---

## 1. High-level design

**Pitch:** You pilot a small submarine out of a sunny atoll dock and dive into "The Blue Hole", a huge
sinkhole that drops through six depth zones. Every dive you catch fish (timing minigame) and salvage
treasure (hold-to-salvage) while oxygen drains, pressure crushes your hull, and predators bump you.
You surface, sell, show off your best catches in your aquarium, upgrade, and push deeper. At the
Hadal Trench you can **Resurface** (rebirth) for a permanent multiplier and access to The Rift.

**Core loop:** Dock → Launch Bay → dive → catch/salvage → manage O₂/hull/cargo → surface (swim up or
hold R) → cargo secured into storage → sell at the Market / display in the Aquarium → buy upgrades →
dive deeper.

### World layout (all procedural, no uploaded assets)

The map is one vertical shaft. Surface is `Y = 0`; 1 stud ≠ 1 metre. Displayed depth maps each zone's
stud band onto its metre band (piecewise linear), so every zone is a similar physical size while the
depth readout climbs from 0 m to 14,000 m.

| # | Zone            | Stud band      | Metres          | Radius | Look / hazard                                        |
|---|-----------------|----------------|-----------------|--------|------------------------------------------------------|
| 1 | Sunlit Shallows | 0 → −300       | 0 – 200         | 460    | Bright sand terraces, kelp, coral, light shafts. Safe |
| 2 | Twilight Reef   | −300 → −700    | 200 – 1,000     | 380    | Dim blue reef ledges, first predators                |
| 3 | Midnight Zone   | −700 → −1,100  | 1,000 – 3,000   | 360    | Near black, glowing coral, lights matter             |
| 4 | Abyssal Plains  | −1,100 → −1,500| 3,000 – 6,000   | 480    | Wide silt plain, shipwreck graveyard, heavy pressure |
| 5 | Hadal Trench    | −1,500 → −1,900| 6,000 – 11,000  | 260    | Narrow trench, ancient ruins, huge creatures         |
| 6 | The Rift        | −1,900 → −2,300| 11,000 – 14,000 | 420    | Alien crystals, neon. Sealed until first rebirth     |

- **Terrain** (FillBlock/FillCylinder/FillBall, carved with Air) builds the atoll ring, the rock
  walls, terraced floors and the holes between zones. **Parts** build the decorations: dock hub,
  kelp, coral, light shafts, shipwrecks, ruins, crystals, aquarium plots and leaderboards.
- Each zone's floor has an offset hole leading to the next zone, so descending means some
  navigating. The Hadal floor's hole is the **Rift Seal**: a client-side barrier for players who
  haven't rebirthed, enforced on the server with a depth clamp.
- A thin terrain-water layer at the surface gives waves and lets players swim at the dock.
  Under it, fog, ambient light and colour correction per zone (driven on the client from camera
  depth) create the underwater look.
- WorldBuilder records **treasure spots** (raycast onto floors, ledges, wreck decks, ruin altars)
  and **fish volumes** per zone for the spawner.

---

## 2. Tech architecture

### Rojo layout

```
default.project.json
src/
  shared/   -> ReplicatedStorage.Shared      (config + pure logic, used by both sides)
  server/   -> ServerScriptService.Server    (authoritative services)
  client/   -> StarterPlayerScripts.Client   (controllers + UI built in code)
  first/    -> ReplicatedFirst.Loading       (loading screen)
tests/      -> pure-Luau unit tests run with the `luau` CLI (not synced to Roblox)
tools/      -> check scripts, economy simulator
```

All UI is built in code by client controllers, so `StarterGui` needs no content. A loading screen
lives in ReplicatedFirst because StarterGui scripts run too late to cover the initial load.

### Shared (`src/shared`)

```
Config/            ALL tunable data (rebalance here, never in logic)
  Game.luau          global tuning: ranges, cooldowns, spawn densities, storage cap, offline cap…
  Rarities.luau      8 tiers: odds, colours, minigame difficulty, claw tier, flee thresholds
  Mutations.luau     Shiny…Voidtouched: odds, multipliers, visuals, event-only flags
  Sizes.luau         weight curve, Colossal roll
  Conditions.luau    Corroded…Flawless
  Zones.luau         geometry, depth mapping, lighting/fog, drain, rarity bonus, hazards
  Fish.luau          78 fish (69 regular + 9 event exclusives)
  Treasure.luau      68 treasures (59 regular + 9 event exclusives)
  TreasureCategories.luau  6 categories with icon + colour
  CollectionSets.luau      13 sets and their permanent bonuses
  Upgrades.luau      8 upgrades × 15 levels, stats + exponential costs
  Rebirth.luau       requirements, multipliers, token shop perks
  Events.luau        schedule constants, 6 events, super event, weekend, effects
  Products.luau      game pass + developer product IDs (placeholders)
  Quests.luau        daily/weekly quest templates by progress tier
  DailyRewards.luau  7-day streak calendar
  Achievements.luau  achievements → skins/titles
  Skins.luau         sub skins
  IndexRewards.luau  codex milestone rewards
  Predators.luau     predator types per zone
  Sounds.luau        every sound slot (placeholder ids, see SOUNDS.md)
  Badges.luau        optional BadgeService ids
  Theme.luau         UI palette, fonts
Modules/
  Types.luau         shared types (Item, PlayerData…)
  Hash.luau          deterministic 32-bit hashing + seeded PRNG (same result on every server)
  LootMath.luau      rarity/mutation/weight/condition rolls, value maths, odds display
  Stats.luau         derived stats from upgrades/passes/perks/sets/boosts/events
  DepthMath.luau     studs ↔ metres, zone lookup
  EventSchedule.luau pure UTC schedule: which event(s) are active at time t
  FishPath.luau      deterministic fish movement (server validates what the client animates)
  Format.luau        number/time formatting
  Signal.luau        tiny signal class
  Net.luau           remote names + typed access
  ModelBuilder.luau  fish, treasure, predator, sub and leviathan models from parts
```

### Server (`src/server`) — authoritative

`Main.server.luau` requires every service, calls `Init()` on all, then `Start()` on all. Services
form a DAG; lower layers talk upward only through `ServerSignals` (no require cycles):

1. **ServerSignals, PlayerState, RateLimiter, Remotes, AnnounceService**
2. **DataService**: ProfileStore (session-locked, autosave, `BindToClose`), data versioning +
   migrations, reconcile, replication to the client (snapshot + deltas)
3. **PassService** (game pass ownership), **BoostService** (server + personal boosts),
   **EventService** (UTC-seeded schedule, local events, countdowns)
4. **StatsService**: per-player derived stats (single source of truth, shared maths)
5. **InventoryService**: add/remove items, cargo vs storage, favourites, sell, blackout loss, auto-sell
6. **WorldService**: procedural world, spots, plots, boards
7. **SubService**: board/launch, sub physics ownership, movement validation, O₂/hull/pressure
   ticks, surfacing, emergency surface, blackout, knockback, refills
8. **SpawnService** (fish/treasure interest-managed streaming with caps + flee), **PredatorService**
9. **LootService**: builds items (mutation, weight, colossal, condition, value, event tag)
10. **CatchService** (minigame sessions), **SalvageService** (hold sessions)
11. **UpgradeService, RebirthService, AquariumService, IndexService** (codex, milestones, sets),
    **QuestService, DailyService, AchievementService** (skins), **CodesService, LeaderboardService,
    TutorialService, MonetizationService** (ProcessReceipt), **NametagService, CosmeticService,
    SettingsService, EventContentService** (Leviathan / Galleon / Tremor), **DebugService** (Studio
    and owner only). Chat tags are applied client-side (ChatController) from player attributes.

`src/server/Config/Codes.luau` is the one config kept server-side: codes in ReplicatedStorage would
be readable by exploiters before release.

### Client (`src/client`)

```
Main.client.luau        boots controllers
Controllers/
  ClientState           data mirror + change signals
  InputController       PC / mobile / console → intents (ContextActionService + PlayerModule)
  MobileControls        big thumb-friendly ACTION, Up/Down, Sonar, Surface, Slow buttons
  SubController         weighty movement (accel, drift, bank, bob), follow camera, shake
  ZoneController        lighting/fog/colour per zone, darkness, event visuals, ambience
  EntityRenderer        pooled fish/treasure/predator/leviathan models, BulkMoveTo animation
  InteractionController target selection, context prompts, catch/salvage intents
  MinigameController    timing bar
  SalvageController     segmented progress ring
  SonarController       ping wave + loot markers
  EffectsController     flash, slow-mo, floating numbers, coin burst, cracks, blackout
  AudioController       SoundGroups, music/ambient crossfades, SFX
  HUDController         depth meter, O₂/hull bars, cargo, coins, event banner/timer, toasts
  MenuController        side bar + tweened menus
  Menus/                Inventory, Index, Upgrades(+Hangar, Resurface), Shop(+Codes), Quests(+Daily)
  RevealController      catch reveal card with escalating sound
  TutorialController    arrows/beams + step prompts, skippable
  AquariumRenderer      renders displayed fish swimming in tanks
  ChatController        VIP/rebirth chat tags, system announcements
  PromptController      tasteful, rate-limited purchase offers
UI/                     UIKit (instance builder, components), Theme usage
```

### Networking and anti-exploit rules

- The client only sends intents. The server does every roll, grant and purchase.
- Every remote goes through `Remotes.bind(name, {rate, burst}, validator, handler)`: token-bucket
  rate limit per player per remote, strict argument type/NaN/range checks, silent drop on failure.
- Distance validation: catch/salvage use server-known sub position vs the server's deterministic
  fish position (`FishPath`) with latency tolerance.
- Sub physics is client-owned for good feel; the server checks every Heartbeat for speed,
  teleports, bounds and the Rift seal, and snaps violators back.
- Minigame taps are validated against the server's marker formula, and the claimed tap time is
  clamped to a latency window.
- Sessions (minigame, salvage) are locked per player and per entity, so first come first served.
- Purchases: idempotent `ProcessReceipt` using a purchase-id cache saved in the profile. It only
  returns `PurchaseGranted` after the save that contains the receipt is confirmed.

### Data (ProfileStore)

Session-locked profiles (`DeepHaul_PlayerData_v1`), autosave every 300 s (ProfileStore default) plus
saves after important events, `BindToClose` handled by ProfileStore, `Version` field and ordered
migration functions, `Reconcile()` for new keys. Studio without API access falls back to a mock
store automatically. Items use compact keys (see `Types.luau`) to stay far under the 4 MB limit.

---

## 3. Key system decisions

- **Rarity is visible, surprises are hidden.** Species (and therefore rarity) is rolled at spawn, so
  a Legendary glows, triggers a "Legendary nearby!" alert and can flee. Mutation, weight/Colossal
  and treasure condition are rolled at catch time for the reveal.
- **Odds:** each non-common tier has an exact `1 in N` chance (checked rarest first), multiplied by
  luck × zone bonus × event multipliers. Common takes the remainder. Mutations are checked rarest
  first with `luck^0.5`. The Index shows your personal live odds.
- **First Legendary guarantee:** if you've found no Legendary+ after 45 min of dive time, the
  next spawn near you is a Legendary (config). This makes the "first Legendary in ~1 hour" target
  reliable.
- **Cargo vs storage:** the cargo hold (upgrade) limits one dive. Surfacing moves cargo into
  storage, which is safe and has a large cap. A blackout loses 50 % of cargo, or none with
  insurance.
- **Surfacing ends the dive:** reaching the surface or holding R returns you to the dock.
- **Silent Running (Ctrl / C, mobile toggle, L3):** caps speed so you can approach skittish fish.
  A "Too fast!" indicator warns you.
- **Sonar** shows loot markers (BillboardGuis, not Highlights, because Highlights cap at 31) and
  stuns nearby predators, which gives you counterplay.
- **Predators** are simulated on the server at 10 Hz (so damage is authoritative) and replicated
  through an UnreliableRemoteEvent; the client interpolates.
- **Fish AI** runs on the client from a deterministic path function the server also evaluates, so
  it costs no per-frame server work.
- **Events:** 45-minute cycles; each cycle's event (or Super Event pair) is picked by hashing the
  UTC cycle index, so every server agrees. 60 s countdown, 10 min duration, weekend luck, local
  "Skip Event Timer" events with a per-server cooldown (a purchase during cooldown is queued).
- **Monetization is convenience/cosmetic only.** Coin packs scale with progression and show the
  exact amount before purchase. The Skip Event Timer is the only random paid item: its exact odds
  are shown and it's hidden for `ArePaidRandomItemsRestricted` players.

---

## 4. Phased build order

Each phase ends with: `tools/check.sh` (rojo sourcemap + luau-lsp strict analysis with Roblox
types + selene + unit tests + rojo build), a self-review, a commit and a push.

| Phase | Scope |
|-------|-------|
| 0 | PLAN.md, Rojo project, tooling (`tools/check.sh`), vendored ProfileStore |
| 1 | Shared config (all content) + pure logic modules + unit tests + economy simulator |
| 2 | Server core: Remotes/RateLimiter, DataService (+migrations, replication), WorldService |
| 3 | Diving: SubService, client Input/Sub/Camera/Zone controllers, HUD bars, surfacing, blackout |
| 4 | Loot: Spawn/Predator/Loot/Catch/Salvage services, EntityRenderer, minigame, salvage ring, reveal |
| 5 | Economy: inventory/sell/favourites, upgrades, rebirth + perks, aquarium + offline, index, sets |
| 6 | Retention: daily streak, quests, leaderboards, codes, achievements/skins, tutorial |
| 7 | Events: schedule, 6 events + exclusives, leviathan, galleon, tremor trenches, blood moon, super/weekend, local events |
| 8 | Monetization: passes, products, receipts, policy, server luck boost, shop, tasteful offers |
| 9 | UI polish and juice: menus, tweens, responsive layout, console navigation, audio, effects |
| 10 | Full review (bugs, exploits, edge cases, performance), README.md, BALANCING.md, SOUNDS.md |

---

## 5. Verification strategy (no Studio in this environment)

- **Type safety:** `luau-lsp analyze` with the official Roblox definitions and a Rojo sourcemap
  catches wrong API names, property types and require paths. Modules use `--!strict`.
- **Lint:** selene with the Roblox standard library.
- **Unit tests:** pure modules (LootMath, Stats, EventSchedule, Hash, DepthMath, FishPath, config
  integrity, data migrations) run under the `luau` CLI in `tests/`.
- **Config integrity test:** every fish/treasure references a valid zone, rarity, model archetype
  and event; every set item exists; every zone has a full pool; every upgrade has at least 10 levels;
  costs grow monotonically.
- **Economy simulation:** `tools/economy_sim.py` models a player's income and upgrade purchases
  to check the pacing targets written up in BALANCING.md.
- **Build:** `rojo build` must produce a place file.
