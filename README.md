# Powered Belts Extended

Use **1.4.0** for Factorio **2.1**, or **1.3.2** for Factorio **2.0**.

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

---

### Power Usage Scales by Entity
Power draw is computed from belt speed and entity type, then scaled by startup settings and efficiency research. Speed scaling is normalized around yellow belt speed (`0.03125`) and supports an exponent startup setting: `(belt_speed^e) / (yellow_belt_speed^e)`.

Default type multipliers:

- Transport belt: `x1`
- Underground belt: `x(max_distance + 3) / 2`
- Splitter: `x5`
- Loader 1x1: `x5`
- Loader: `x10`

Underground belt power is calculated from the pair’s maximum segment length, plus 2 for down/up transitions, then divided by 2 so each end consumes half.

---

### On/Off Behavior During Brownouts
Belts switch between powered and unpowered variants based on stored energy in hidden power interfaces.  
This is threshold-based switching, not gradual speed throttling.

In edge cases, this means a tiny power source can keep many belts running as long as they do not drop below the threshold.

During brownouts, entities can switch at different times depending on:

- input flow limit,
- buffer capacity,
- effective threshold,
- update-order timing.

This can stall lines (especially fuel routes) and delay recovery.


Entities marked for deconstruction are not toggled by this logic to avoid interfering with planner/ghost behavior.

---

### Power Buffer Mechanics (Technical)
For each powered belt entity:

- `energy_usage = ei` (kW)
- `input_flow_limit_kw = max(ei, ei*ifl_mult + 0.1*ifl_flat)`
- `buffer_capacity_kj = max(0.001, ei*bc_mult)` (`>= 1J`)

Runtime threshold values:

- `X = clamp(threshold_pct + threshold_flat, 0, 100)`
- `H = clamp(hysteresis_pct, 0, 33) / 100`
- `down_pct = clamp((1-H)*X, 0, 100)`
- `up_pct = clamp((1+H)*X, 0, 100)`

Switching rules:

- power down when `energy < down_energy`,
- power up when `energy >= up_energy`.

Boundary behavior is intentional: near `0%`/`100%`, one side of the hysteresis window shrinks (possibly to zero).

Approximate timings from idealized states:

- `t_off ~= (B - B*down_pct/100) / ei`
- `t_on ~= (B*up_pct/100) / max(I - ei, 0)` where `I = input_flow_limit_kw` and `B = buffer_capacity_kj`

---

### Preset Modes
- `default`
  Legacy behavior: higher-usage entities typically need longer to charge, so different entities (and often tiers) can power up/down at different times.

- `synchronized`
  Ratio-based tuning with no flat offsets, targeted to keep different entity types closer in transition timing.
  Also tuned so idealized full-charge startup time and full-discharge shutdown time are equal.

- `responsive`
  Same synchronization goal, but faster reaction to grid changes (higher charge headroom, smaller buffers).
  Adds hysteresis to reduce rapid flicker in unstable networks and lower replacement churn/UPS overhead.

- `custom`
  Enables detailed tuning. Defaults mirror `default`, so switching to `custom` does not change behavior until edited.

Preset-locked values:

- `default`: `ifl_mult=1.0`, `ifl_flat=10`, `bc_mult=1.0`, `threshold_pct=50`, `threshold_flat=0`, `hysteresis=0`
- `synchronized`: `ifl_mult=2.0`, `ifl_flat=0`, `bc_mult=1.0`, `threshold_pct=50`, `threshold_flat=0`, `hysteresis=0`
- `responsive`: `ifl_mult=5.0`, `ifl_flat=0`, `bc_mult=0.25`, `threshold_pct=50`, `threshold_flat=0`, `hysteresis=10`

---

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
- `powered-belts-energy-behavior-preset` (default `default`)
  Selects energy behavior profile: `default`, `synchronized`, `responsive`, or `custom`.
- `powered-belts-input-flow-limit-multiplier` (default `1.0`, min `1.0`, max `10.0`)
  Detailed startup tuning, active only when preset is `custom`.
- `powered-belts-input-flow-limit-flat` (default `10`, min `0`, max `100`)
  Detailed startup tuning, active only when preset is `custom`. Each point adds `0.1kW`.
- `powered-belts-buffer-capacity-multiplier` (default `1.0`, min `0.01`, max `10.0`)
  Detailed startup tuning, active only when preset is `custom`.
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
  Detailed runtime tuning, active only when preset is `custom`. Base threshold percentage.
- `powered-belts-required-energy-percentage-flat` (default `0`, min `0`, max `100`)
  Detailed runtime tuning, active only when preset is `custom`. Flat percentage-point offset added before hysteresis.
- `powered-belts-required-energy-hysteresis-percentage` (default `0`, min `0`, max `33`)
  Detailed runtime tuning, active only when preset is `custom`. Defines split between power-up and power-down thresholds.
- `powered-belts-print-underground-spillage` (default `true`)
  Prints `[PBE]` chat messages when underground fallback handling spills items.


---

## Other Features

- Incremental on-tick processing (`operations-per-tick`) to bound update cost.
- Full consistency checks that repair error states are run on init and configuration changes.
- Supports multiple surfaces and keeps entity tracking partitioned per surface.
- Unpowered variants preserve original `placeable_by` which enables pipette and blueprint usage.

---

## Compatibility: 

### AAI Loaders

#### Implemented Behavior

When `aai-loaders` is active, Powered Belts Extended applies targeted compatibility logic for AAI loader entities only (`aai-*` / `unpowered-aai-*`).

- Power-up replacement (`unpowered-aai-*` -> `aai-*`) is created with `raise_built=true` so that AAI Loaders track internally the replaced loader.
- Power-down replacement (`aai-*` -> `unpowered-aai-*`) proactively removes the AAI helper pipe before swap. Unpowered loaders are purposefully not tracked by AAI loaders mod not to consume lubricant while inactive.
- Keeps track of extra fluid that would be lost due to helper pipe being removed (occurs if pipeline capacity reached after removal) and later attempts to restore it.
- Compatibility logic is scoped; non-AAI entities keep the normal replacement flow and without raising events.

#### Why This Is Needed

AAI Loaders tracks lubricated loaders internally and manages helper pipe entities. Without targeted handling, fast-replace power toggles leaves invalid AAI loader entry that is not initialized properly without built event being raised (and as such - doesn't consume lubricant). The removal of the old pipe is needed to make space for a new one that will belong to powered-up loader that according to AAI internals - might otherwise "inherit" the stale pipe after, now an invalid entity, instead of creating a fresh one - which would later cause removal of currently used helper pipe that originally belonged to that invalid entity.

#### Compatibility Effects

- In AAI `lubricated` mode: loader requires both PBE power and AAI lubricant.
- In AAI `expensive` mode: loader requires PBE power only.
- Prevents invalid states and significant fluid loss across repeated brownouts (lost registration/orphan loader state).

#### Limits / Fragility

Each power-down and power-up cycle causes lubricated AAI Loader to consume initial lubricant upfront again (1.0 or rate-per-minute if higher than 1.0) and resets its refresh cycle.

This compatibility relies on current AAI conventions:

- Helper pipe name: `<powered_loader_name>-pipe`
- Helper pipe position: `{x = loader.x, y = loader.y + 1/32}`

If a future AAI Loaders release changes naming/placement/ownership internals, PBE compatibility is best-effort and will fail soft (normal belt power behavior continues, and warnings are logged).

#### Tested Versions

- Powered Belts Extended: `1.4.0` (Factorio 2.1.23)
- AAI Loaders: `0.3.0`

### Community Tested Mods

Below are mods that have been used by Powered Belts Extended testers/users and some of them had compatibility issues resolved previously. While they might work with this mod - they are not thoroughly tested, nor full compatibility is guaranteed. These mods include:

- AAI Loaders - described in detail in previous section
- Black Rubber Belts - Remastered - resolved issue with icons
- Loader Utils - resolved issue with mod loading order
- Deadlock's Stacking Beltboxes & Compact Loaders - was used alongside Loader Utils

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

<!-- PORTAL-DESCRIPTION-END: copy everything above this line to the mod portal. -->

---

## Development

Repository-only notes below this boundary are not part of the portal description.

- [Engine scenarios and commands](tests/README.md)
- [Run modes and debugging](tests/integration/RUN_MODES.md)
- `scripts/package-mod.ps1` or `scripts/package-mod.sh` builds a release archive.
- Use an actual Factorio 2.1 engine for this branch. The `factorio-2.0` branch retains 1.3.2. Tests run in isolated profiles.
