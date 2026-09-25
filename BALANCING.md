# DEEP HAUL — Balancing

All numbers live in `src/shared/Config`. This file explains the pacing targets, the maths behind
the loot, and what the economy simulator says. Re-run the simulator after any tuning change:

```
python3 tools/bundle_tests.py --script tools/economy_sim.luau && luau build/script_bundle.luau
```

The simulator uses the real config and loot maths (`Stats`, `LootMath`, `Config/*`) with a simple
player model: it dives as deep as its hull comfortably allows, picks the rarest of the few fish in
view, sometimes misses the minigame, salvages the best treasure its claw allows, surfaces when
cargo is full or oxygen runs low, sells everything and spends greedily on upgrades. No passes, no
events, no boosts, no Index or set bonuses, so real players progress somewhat faster.

## Pacing targets vs. simulation

24 runs, no passes or events (median with 10th-90th percentile):

| Milestone | Target | p10 | Median | p90 |
|---|---|---|---|---|
| First Legendary | about 1 hour | 5 min | **31 min** | 52 min |
| First dive into Twilight Reef | minutes | 5 min | 8 min | 10 min |
| Reach Midnight Zone | | 24 min | 33 min | 45 min |
| Reach Abyssal Plains | | 3.1 h | 4.0 h | 4.5 h |
| **Reach Hadal Trench** | 15-20 hours | 15.3 h | **18.7 h** | 22.3 h |
| **First rebirth (Resurface)** | about 25 hours | 19.0 h | **23.4 h** | 27.4 h |

Safety net: a player who has dived for `Game.Spawns.FirstLegendaryGuaranteeMinutes` (45) without a Legendary gets one
spawned for them (retried every 5 minutes), so nobody waits much longer than an hour.

Income per zone in the simulation: Shallows 8.7K/h, Twilight 100K/h, Midnight 970K/h,
Abyssal 11M/h. Each zone is roughly 10× the one above, and upgrade prices grow about 3× per
level, which is what keeps every zone relevant for a few hours.

## Rarity (exact odds)

The chance of each tier is exactly `1 / odds × luck × zone rarity bonus × event multiplier`,
filled from the rarest tier down. Uncommon-and-rarer is capped at 95% in total, and Common gets
whatever is left. Rarity is rolled when the fish or treasure spawns, so rare loot is visible (it
glows, and it can flee).

| Rarity | Base odds | Minigame green zone | Claw tier |
|---|---|---|---|
| Common | remainder (~75%) | 32% of the bar | 1 |
| Uncommon | 1 in 5 | | 1 |
| Rare | 1 in 25 | | 2 |
| Epic | 1 in 150 | | 3 |
| Legendary | 1 in 1,000 | | 4 |
| Mythic | 1 in 10,000 | | 5 |
| Abyssal | 1 in 100,000 | | 6 |
| Secret | 1 in 1,000,000 | 9% of the bar | 7 |

Zone rarity bonus: Shallows 1.0, Twilight 1.3, Midnight 1.7, Abyssal 2.2, Hadal 3.0, Rift 4.0.
The Index shows each player their exact odds for every species, including their current luck and
any active events.

## Mutations, size and condition

These are rolled when you catch a fish. Mutation chance scales with `luck^0.5` so luck helps but
doesn't break it.

| Mutation | Odds | Value |
|---|---|---|
| Shiny | 1 in 50 | ×2 |
| Albino | 1 in 200 | ×3 |
| Glowing | 1 in 500 (×10 in Bloom) | ×5 |
| Golden | 1 in 2,000 (×5 in Golden Tide) | ×10 |
| Shadow | 1 in 5,000 | ×20 |
| Prismatic | 1 in 25,000 | ×50 |
| Voidtouched | 1 in 5,000, **Blood Moon only** | ×100 |

- **Weight:** a curve inside each species' range; heavier fish are worth 0.6×-1.5×.
- **Colossal:** 1 in 500, worth ×5 and shown at 3× scale.
- **PERFECT catch** (marker in the centre 30% of the green zone): ×1.1 value.
- **Treasure condition:**
  - Weighted rolls: Corroded ×0.5, Worn ×1, Intact ×2, Pristine ×5. Luck boosts Intact and Pristine (`luck^0.35`).
  - Flawless ×15 is an exact 1-in-1,000 roll.

## Upgrades (15 levels each)

| Upgrade | Level 1 → 15 | Cost of level 2 · 5 · 10 · 15 | Total |
|---|---|---|---|
| Hull Plating (max depth, m) | 250 → 14,000 | 400 · 20K · 22M · 8B | 10.8B |
| Oxygen Tank (seconds) | 120 → 1,000 | 100 · 2.7K · 660K · 160M | 239M |
| Engine (speed) | 28 → 104 | 90 · 2.4K · 590K · 140M | 211M |
| Floodlights (light radius) | 45 → 330 | 120 · 3.2K · 790K · 190M | 285M |
| Sonar (range) | 80 → 380 | 110 · 2.7K · 550K · 110M | 169M |
| Cargo Hold (slots) | 10 → 60 | 80 · 2.3K · 600K · 160M | 237M |
| Salvage Claw (tier) | 1 → 7 | 110 · 3K · 720K · 180M | 266M |
| Luck Module (+%) | 0 → 170 | 160 · 4.5K · 1.2M · 320M | 470M |

Hull is the pacing gate: going below your hull's max depth drains the hull quickly, so each new
zone needs an explicit hull purchase. Hull prices are a hand-tuned table (`Upgrades.luau`); the
others use `base × growth^(level-2)` with prices rounded to "nice" numbers.

## Rebirth (Resurface)

- **Requirements:** you must have reached the Hadal Trench (6,000m) once, and hold
  `60M × 3^n` coins (60M, 180M, 540M, 1.6B, 4.9B, …).
- **Resets:** coins and upgrades.
- **Keeps:** items, Index, aquarium, skins, quests and achievements.
- **Rewards:**
  - +0.5 sell multiplier per rebirth (×1.5, ×2, ×2.5, …).
  - `3 + n` rebirth tokens for the perk shop (starting upgrade levels, luck, sell, oxygen and more, plus the Phoenix skin).
  - A nametag and chat badge.
  - The first rebirth opens The Rift.

## Other income

- **Aquarium:** displayed items earn 0.2% of their value per minute, online and offline, with offline earnings capped at 8 hours.
- **Index milestones:** 25/50/75/100% per zone and per treasure category, plus the whole Index. They pay coins scaled to the zone, and the 100% milestones add permanent luck.
- **Collection sets:** 13 sets, each with a permanent bonus.
- **Quests:** coin rewards scale with your deepest zone (`coinScale` 1, 4, 15, 60, 240, 1000). Weekly quests pay 6× and grant a Luck Boost (plus a token after your first rebirth).
- **Daily streak:** also scales with your deepest zone; day 7 is the jackpot.

## Events

- **Schedule:** one every 45 minutes, running for 10 minutes, with a 60-second countdown. The schedule is seeded from UTC, so every server runs the same event at the same moment. 5% of events are Super Events (two at once).
- **Weekends (UTC):** ×1.5 luck all weekend, and ×1.25 more during events.

| Event | Effect |
|---|---|
| Bioluminescent Bloom | Glowing ×10, 12% exclusive spawns |
| Leviathan Migration | Wake loot at ×4 luck behind the Leviathan (Abyssal Plains) |
| Sunken Galleon | 26 Rare+ treasures at ×6 luck, 35% Galleon exclusives |
| Golden Tide | Golden ×5, sell prices ×1.5 |
| Deep Tremor | 9 trenches holding Tech/Cursed-weighted treasure at ×2 luck |
| Blood Moon Tide | Mythic, Abyssal and Secret ×3, Voidtouched enabled, predators ×1.8 aggro and ×2 density |

## Monetization and fairness

- No fish or treasure can be bought.
- Passes are modest multipliers: +20% sell (VIP), 2× cargo, +25% luck, +30% speed, +4 tanks.
- Coin packs scale with progress, so they stay a small top-up, never a skip to the end.
- The only random item, Skip Event Timer, shows its exact odds (1 in 6 for each event). It is hidden for players where PolicyService restricts paid random items.
