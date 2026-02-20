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

### Power Usage Scales by Entity
Power draw is computed from belt speed and entity type, then scaled by startup settings and efficiency research.

Default type multipliers:

- Transport belt: `x1`
- Underground belt: `x(max_distance + 2)`
- Splitter: `x5`
- Loader 1x1: `x5`
- Loader: `x10`

### On/Off Behavior During Brownouts
Belts are switched between powered and unpowered variants based on local stored energy.

- If energy falls below threshold, the entity is powered down.
- When energy recovers, it powers back up.

Note: behavior is threshold-based (on/off), not gradual speed throttling.

In edge cases, this means a tiny power source can keep many belts running as long as they do not drop below the threshold.

### Underground Belt Item Safety

In similar mods (and originally in Powered Belts) items in underground belts disappear due to sequential entity replacement which immediately breaks their transport lines and removes held items from the game. 
This version implements replacement logic that preserves items in a temporary inventory while entities are swapped and then places them back in their original positions if possible - otherwise, as a fallback, items are spilled at the underground belt's position.


---

## Technology: Belt Transport Efficiency

Five upgrade levels are added (`efficient-belts-1` to `efficient-belts-5`).

- Each level reduces belt-related power usage by the configured startup fraction.
- Reduction stacks multiplicatively.
- Default reduction is `20%` per level (`100% -> 80% -> 64% -> 51.2% -> ...`).

---

## Settings

### Startup

- `powered-belts-usage-multiplier` (default `0.2`)
  Scales all belt power usage globally.
- `powered-belts-upgrade-reduction` (default `0.2`)
  Per-level fractional reduction used by efficiency research.

### Runtime Global

- `powered-belts-operations-per-tick` (default `16`)
  How many belt power entities are processed each tick.


---

## Other Features

- Incremental on-tick processing (`operations-per-tick`) to bound update cost.
- Full consistency checks that repair error states are run on init and configuration changes.
- Supports multiple surfaces and keeps entity tracking partitioned per surface.

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

