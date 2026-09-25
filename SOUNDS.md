# DEEP HAUL — Sounds

Every sound in the game is a slot in `src/shared/Config/Sounds.luau`. All slots ship as `rbxassetid://0` (placeholder).

**To add audio:** upload or pick a sound in the Creator Store (it must be public or owned by the experience owner), copy its asset id, and replace `rbxassetid://0` with `rbxassetid://<id>` in `Sounds.luau`. Nothing else needs changing.

**Missing audio never breaks the game:** a slot left at `rbxassetid://0` plays its built-in Roblox *fallback* sound if it has one, and is silently skipped otherwise.

Groups map to the volume sliders in Settings: **SFX** (effects), **Music** (soundtrack), **Ambient** (follows the SFX slider at 90%).

| Slot | Group | Volume | Loop | Built-in fallback | What it should sound like |
|---|---|---|---|---|---|
| `UIClick` | SFX | 0.5 |  |  | Short soft click on any button |
| `UIHover` | SFX | 0.25 |  |  | Very quiet tick on hover |
| `UIOpen` | SFX | 0.45 |  |  | Menu whoosh/pop open |
| `UIClose` | SFX | 0.4 |  |  | Menu close |
| `UIError` | SFX | 0.5 |  |  | Soft "nope" buzz |
| `Notify` | SFX | 0.45 |  |  | Toast / popup chime |
| `Purchase` | SFX | 0.6 |  |  | Cash-register sparkle |
| `Upgrade` | SFX | 0.7 |  |  | Mechanical clunk + rising chime |
| `CoinGain` | SFX | 0.6 |  |  | Coins landing in the counter |
| `CoinBurst` | SFX | 0.75 |  |  | Big coin shower (selling) |
| `QuestComplete` | SFX | 0.7 |  |  | Short fanfare |
| `DailyClaim` | SFX | 0.7 |  |  | Chest opening + sparkle |
| `Achievement` | SFX | 0.75 |  |  | Triumphant sting |
| `Rebirth` | SFX | 0.9 |  |  | Big magical whoosh / choir hit |
| `SubLaunch` | SFX | 0.7 |  | impact_water.mp3 | Splash + motor start |
| `SubSurface` | SFX | 0.7 |  | impact_water.mp3 | Breaking the surface splash |
| `EngineHum` | SFX | 0.25 | yes |  | Low electric motor loop |
| `Bubbles` | SFX | 0.2 | yes | action_swim.mp3 | Bubble stream loop |
| `SonarPing` | SFX | 0.7 |  | electronicpingshort.wav | Classic sonar ping |
| `SonarBlip` | SFX | 0.35 |  | electronicpingshort.wav | Short high blip per revealed item |
| `PressureCreak` | SFX | 0.6 |  |  | Metal hull groan |
| `HullCrack` | SFX | 0.8 |  |  | Sharp crack/clank |
| `Alarm` | SFX | 0.45 | yes |  | Low-oxygen/hull alarm loop |
| `OxygenLow` | SFX | 0.45 | yes |  | Breathing/heartbeat loop |
| `Impact` | SFX | 0.8 |  |  | Heavy thud (predator hit) |
| `PredatorGrowl` | SFX | 0.6 |  |  | Deep underwater growl |
| `Emergency` | SFX | 0.8 |  |  | Emergency ballast blow |
| `Blackout` | SFX | 0.8 |  |  | Muffled fade-out whoomp |
| `Refill` | SFX | 0.7 |  |  | Air hiss / repair ding |
| `MinigameStart` | SFX | 0.5 |  |  | Tense short riser |
| `CatchSuccess` | SFX | 0.7 |  |  | Reel-in success |
| `CatchPerfect` | SFX | 0.8 |  |  | Bright "perfect" ding |
| `CatchFail` | SFX | 0.7 |  | impact_water.mp3 | Splash + line snap |
| `SalvageLoop` | SFX | 0.4 | yes |  | Claw servo loop |
| `SalvageDone` | SFX | 0.7 |  |  | Clamp + clink |
| `RareNearby` | SFX | 0.6 |  |  | Shimmering alert |
| `RevealCommon` | SFX | 0.5 |  |  | Catch reveal sting for Common rarity (escalating grandeur) |
| `RevealUncommon` | SFX | 0.55 |  |  | Catch reveal sting for Uncommon rarity (escalating grandeur) |
| `RevealRare` | SFX | 0.6 |  |  | Catch reveal sting for Rare rarity (escalating grandeur) |
| `RevealEpic` | SFX | 0.7 |  |  | Catch reveal sting for Epic rarity (escalating grandeur) |
| `RevealLegendary` | SFX | 0.8 |  |  | Catch reveal sting for Legendary rarity (escalating grandeur) |
| `RevealMythic` | SFX | 0.9 |  |  | Catch reveal sting for Mythic rarity (escalating grandeur) |
| `RevealAbyssal` | SFX | 0.95 |  |  | Catch reveal sting for Abyssal rarity (escalating grandeur) |
| `RevealSecret` | SFX | 1 |  |  | Catch reveal sting for Secret rarity (escalating grandeur) |
| `EventCountdown` | SFX | 0.5 |  |  | Countdown tick before an event |
| `EventStart` | SFX | 0.85 |  |  | Event start horn / fanfare |
| `EventEnd` | SFX | 0.6 |  |  | Event ending chime |
| `TremorRumble` | SFX | 0.9 |  |  | Deep earthquake rumble |
| `LeviathanCall` | Ambient | 0.9 |  |  | Enormous distant whale/serpent call |
| `WhaleCall` | Ambient | 0.5 |  |  | Distant whale song |
| `AmbientDock` | Ambient | 0.4 | yes |  | Dock ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientShallows` | Ambient | 0.4 | yes |  | Sunlit Lagoon and Coral Kingdom ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientTwilight` | Ambient | 0.4 | yes |  | Kelp Cathedral and Twilight Drift ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientMidnight` | Ambient | 0.45 | yes |  | Glowvein Caverns and Midnight Abyss ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientAbyssal` | Ambient | 0.45 | yes |  | Wreck Graveyard and Frostvent Trench ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientHadal` | Ambient | 0.5 | yes |  | Hadal Maw ambience bed (water, distant creaks, whale calls for deep zones) |
| `AmbientRift` | Ambient | 0.5 | yes |  | Rift ambience bed (water, distant creaks, whale calls for deep zones) |
| `MusicDock` | Music | 0.35 | yes |  | Dock music loop |
| `MusicShallows` | Music | 0.35 | yes |  | Sunlit Lagoon and Coral Kingdom music loop |
| `MusicTwilight` | Music | 0.35 | yes |  | Kelp Cathedral and Twilight Drift music loop |
| `MusicMidnight` | Music | 0.35 | yes |  | Glowvein Caverns and Midnight Abyss music loop |
| `MusicAbyssal` | Music | 0.35 | yes |  | Wreck Graveyard and Frostvent Trench music loop |
| `MusicHadal` | Music | 0.35 | yes |  | Hadal Maw music loop |
| `MusicRift` | Music | 0.35 | yes |  | Rift music loop |
| `MusicBloom` | Music | 0.4 | yes |  | Bloom music loop |
| `MusicLeviathan` | Music | 0.4 | yes |  | Leviathan music loop |
| `MusicGalleon` | Music | 0.4 | yes |  | Galleon music loop |
| `MusicGolden` | Music | 0.4 | yes |  | Golden music loop |
| `MusicTremor` | Music | 0.4 | yes |  | Tremor music loop |
| `MusicBloodMoon` | Music | 0.4 | yes |  | BloodMoon music loop |
