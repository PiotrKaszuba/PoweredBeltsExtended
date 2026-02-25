# Powered Belts Extended

**Belts now need power in Factorio 2.0+**

`Powered Belts Extended` makes every belt network entity consume electricity, including modded entities. Transport belts, underground belts, splitters, and loaders are monitored and automatically switch off during power shortages.

- Mod Portal: https://mods.factorio.com/mod/PoweredBeltsExtended
- GitHub: https://github.com/PiotrKaszuba/PoweredBeltsExtended

---

## Core Mechanics

### Everything Belt-Like Needs Power
The mod creates hidden electric power entities for:

- `transport-belt`
- `underground-belt`
- `splitter`
- `loader`
- `loader-1x1`

This includes vanilla and modded prototypes present in the game.

Helper power entities and unpowered belt variants are localized and hidden from Factoriopedia to reduce UI clutter.

### Power Usage Scales by Entity
Power draw is computed from belt speed and entity type, then scaled by startup settings and efficiency research. Speed scaling is normalized around yellow belt speed (`0.03125`) and supports an exponent startup setting: `(belt_speed^e) / (yellow_belt_speed^e)`.

Default type multipliers:

- Transport belt: `x1`
- Underground belt: `x(max_distance + 3) / 2`
- Splitter: `x5`
- Loader 1x1: `x5`
- Loader: `x10`

Underground belt power is calculated from the pair’s maximum segment length, plus 2 for down/up transitions, then divided by 2 so each end consumes half.

### On/Off Behavior During Brownouts
Belts are switched between powered and unpowered variants based on local stored energy.

- If energy falls below the configured buffer-percentage threshold, the entity is powered down.
- When energy recovers to that threshold, it powers back up.

Note: behavior is threshold-based (on/off), not gradual speed throttling.

In edge cases, this means a tiny power source can keep many belts running as long as they do not drop below the threshold.

### Underground Belt Item Safety

In similar mods (and originally in Powered Belts) items in underground belts disappear due to sequential entity replacement which immediately breaks their transport lines and removes held items from the game. 
This version implements replacement logic that preserves items in a temporary inventory while entities are swapped and then places them back in their original positions if possible - otherwise, as a fallback, items are spilled at the underground belt's position.


---

## Technology: Belt Transport Efficiency

Configurable upgrade levels are added (`efficient-belts-1` to `efficient-belts-N`, where `N` is startup setting `powered-belts-num-upgrades`).

- Each level reduces belt-related power usage by the configured startup fraction.
- Reduction stacks multiplicatively.
- Default reduction is `20%` per level (`100% -> 80% -> 64% -> 51.2% -> ...`).
- Science pack count per level is configurable via `powered-belts-efficiency-tech-cost-per-level` (default `50`).
  - `25` = half cost (`0.5x`), `50` = vanilla mod default (`1x`), `200` = four times cost (`4x`).
  - This scaling also applies to the higher incremental costs on levels above 6.

---

## Settings

### Startup

- `powered-belts-usage-multiplier` (default `0.2`)
  Scales all belt power usage globally.
- `powered-belts-speed-exponent` (default `1.0`, min `0.0`, max `3.0`)
  Controls nonlinear speed-to-power scaling around yellow belt speed (`0.03125`). `1.0` matches linear behavior.
- `powered-belts-efficiency-tech-cost-per-level` (default `50`, min `25`, max `200`)
  Base science cost per efficiency technology level. `25` = `0.5x`, `50` = `1x`, `200` = `4x`.
- `powered-belts-num-upgrades` (default `5`, min `0`, max `10`)
  Sets how many efficiency upgrade technologies are generated.
- `powered-belts-upgrade-reduction` (default `0.2`)
  Per-level fractional reduction used by efficiency research.

### Runtime Global

- `powered-belts-operations-per-tick` (default `16`)
  How many belt power entities are processed each tick.
- `powered-belts-required-energy-percentage` (default `50`, min `0`, max `100`)
  Percentage of each entity energy buffer that must be available for it to stay powered.


---

## Other Features

- Incremental on-tick processing (`operations-per-tick`) to bound update cost.
- Full consistency checks that repair error states are run on init and configuration changes.
- Supports multiple surfaces and keeps entity tracking partitioned per surface.
- Unpowered variants preserve original `placeable_by` which enables pipette and blueprint usage.

---

## Known Limitations

- Tooltip power values on item/entity hover are static summaries, not live values at current efficiency tech level. Power sources in the electric network statistics will show current power consumption values in tooltips when hovered.
- Underground belt power draw is currently based on prototype max distance, not the actually built pair length.
- When placing an underground belt manually against an existing unpowered endpoint, vanilla underground distance/arrows helper overlay will not appear even if placement is valid.
- Additionally (to the above), both underground belt ends will be treated as an 'input' end (because engine does not recognize them as a matching pair) - so unless one of them is then manually rotated to become an 'output' end with matching direction - the first belt that changes it powered/unpowered state will change its direction to match the other end (automatically by the engine pairing mechanism).
- If underground belt ends from a matched pair are powered by separate electric networks and if one of the networks is low on power and would turn off their undeground end while the other end remains powered; it will result in alternating powered and unpowered states of the underground pair with the duration of each state determined by the the internal order of belt entities held by the mod and the amount of ticks it takes to loop through all entities. If there are too few entities handled by the mod causing it to loop through the underground pair often - it will keep emitting smoke and might become unable to be interacted with due to constant replacement.
- Production statistics for deconstruction will show separate entries for powered and unpowered variants of the same belt entity (built entities are all counted as powered variants).
- Electric network statistics will split historical consumption across multiple hidden power-interface prototypes when viewing a time range that spans different efficiency tech levels.

---

## Troubleshooting

Use this command to rescan and repair tracked power entities:

```text
/PBE_CheckPowerEntities
```

It checks belt-to-power-entity consistency and removes or repairs orphaned/incorrect entries.


---

## Credits

This project builds on Powered Belts by Romner_set: https://mods.factorio.com/mod/PoweredBelts.

