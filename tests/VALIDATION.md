# Factorio 2.1 validation

27 October 2026. Candidate **1.4.0**, based on 2.0 baseline `e40f932`.
Actual engine: **2.1.23 Windows Steam**, isolated base-game profiles; expansion
modules disabled. Historical 2.0 evidence follows unchanged below.

## Production scope

Only two runtime files differ from the accepted 2.0 baseline:

- `undergrounds.lua`: `neighbours` → `underground_belt_neighbour` at all eight reads.
- `compatibility.lua`: AAI snapshots read segment fluid/capacity explicitly and
  use `get_fluid_capacity(1)` for the removed pipe's own volume. The saved amount
  remains `max(0, segment_amount - (segment_capacity - pipe_capacity))`.

Power formulas, thresholds/cache, settings, prototypes, locale, item preservation,
planner handling, scanning and persistent state layout are unchanged. No gameplay
redesign or new migration is involved. AAI 0.3.0 retains 0.2.11's rate/settings and
startup/refresh charges; its own code also ports active writes and fluid APIs.
Individual-storage fluid reads differ from segment reads in 2.1, which is why a
simple method-name substitution would be insufficient for PBE snapshots.

## Final archive acceptance

`PoweredBeltsExtended_1.4.0.zip`: **20 files / 402102 bytes**; SHA-256
`adbddac1c92426a9c43a5e126bba08cf0091a142bba6f87e8fcdb23f4b02f5d5`.
CRC, single mod root, portable ZIP paths and every packaged source byte match.
No test module is packaged. The original accepted 1.3.2 archive remains unchanged.

| Exact-archive profile | Orders / runs | Scenarios / assertions per run |
| --- | --- | --- |
| Production base acceptance | Normal, reversed | 8 / 36, all pass |
| Four isolated presets | Normal, reversed for each | 1 / 3 each; Custom 1 / 6, all pass |
| Combined partner set, AAI lubricated | Normal, reversed | 16 / 76, all pass |
| AAI expensive mode | Normal, reversed | 9 / 42, all pass |
| Save/restart during planner outage | Two server processes | 1 / 7, pass |
| Real 2.0.77/1.3.2 → 2.1.23/1.4.0 planner checkpoint | Saved at 400, version change at 401 | 1 / 7, pass through 1800 |
| Same upgrade with AAI 0.2.11 → 0.3.0 during outage | Saved at 350, version change at 351 | 1 / 12, pass through 1000 |

The combined partner set uses AAI Loaders **0.3.0**, Loader Utilities **1.2.2**,
Perel **1.2.2**, Black Rubber Belts Remastered **2.4.6**, Dredgeworks **1.0.0** and
Dredgeworks Graphics **1.0.0**. Archive SHA identities are in generated reports.
All ordinary archive trials use the production 16 operations/tick. Timing profiles
explicitly use 128. The final matrix totals **77 scenario executions / 364
assertions**. The earlier complete source suite also passes normal/reversed and
its disabled-mod negative controls, plus all eight preset/order profiles.

Connected AAI trials check partial/full segments: fluid retained by a surviving
pipe plus any PBE snapshot stays within the expected AAI consumption allowance,
without duplication; overflow is restored and its snapshot cleared. Both snapshot
and no-snapshot paths pass. The real AAI upgrade checkpoint carries pending fluid
state through the game/mod update. It is not a synthetic reconstruction after load.

Actual Dredgeworks floating belts are exercised on water at all three base tiers,
with observed off/on transitions and complete transfer. Issue #11's reported
collision-mask loading failure **does not reproduce with this partner set**; no
speculative production patch was added. The reporter's complete original mod list
is unknown, so this does not establish the cause or certify arbitrary combinations.

Default/Synchronized/Responsive transitions match the recorded 2.0 fixture ticks
exactly, in both orders. Custom still verifies the 48%/72% deadband. These remain
bounded observations, not universal synchronization or unchanged engine-flow claims.

## Performance and limits

No additional polling, scans, per-tick storage or algorithmic work was introduced.
The threshold implementation is byte-identical to 1.3.2. Five fresh Lua 5.2.4
workload samples (1000 ticks) give median CPU totals **0.006 s** at 16 checks/tick
(range 0.002–0.012), **0.289 s** at 1024 (0.264–0.302). These are consistent with
the earlier accepted measurements; they do not measure total native-mod UPS or
establish cross-engine performance equivalence. Lua syntax passes for 32 files;
Python compilation and the policy/cache regression pass.

Commands and upgrade-checkpoint semantics: [README.md](README.md). Raw accepted
runs stay ignored under `tests/artifacts/release-1.4.0-*`; preparatory native
checkpoints/source trials under `port-2.1-*`. AAI/Dredgeworks fixtures are retained
as ordinary acceptance scenarios. RCON, actual player/robot cursor routes and
Space Age implementation are not newly certified by this port.

---

# Factorio 2.0 validation

27 October 2026. Actual engine: **2.0.77 Linux headless**, base game only.
Review baseline: `d056f21` (presets/hysteresis). The follow-up fixes its settings
resolver and reduces repeated threshold work; it does not port anything to 2.1.

## Findings and fixes

- Runtime settings containers are `LuaCustomTable` userdata. Rejecting anything
  except a plain table made runtime preset/Custom resolution fall back to 50% with
  no hysteresis. A real custom 48%/72% band trial reproduced this before the fix.
  Data-stage helper sizing already respected presets, so the bug also made runtime
  thresholds disagree with the configured helper behavior.
- Threshold configuration is now resolved once per game tick, with immediate
  invalidation for a changed test-override table. It is module-local derived data,
  not saved state; reload/configuration changes start with an empty cache. Production
  belt checks reuse that one result. Runtime setting changes take effect by the
  next processed tick, without a migration or per-entity stored setting.
- Timing assertions formerly read phase metrics before finalization; they could
  fail despite correct recorded transitions. Metrics are now current at checkpoints.
- Windows packaging now writes one required mod-root directory and forward-slash
  ZIP entries. CRCs and all 20 packaged files were checked against source; the test
  module is deliberately excluded. The Linux headless runner now uses explicit
  data paths, the actual staged mod-list and no bundled expansion mods.

## Native matrix

| Input / profile | Build orders | Scenarios per order / result |
| --- | --- | --- |
| Complete source suite, including diagnostic transfer modes | Normal, reversed | 15 / passed each; 65 assertions each |
| Disabled-mod controls, initial baseline | Normal | 15 expected outcomes; intentional failing assertions are checked as negative controls |
| Exact ZIP, production base acceptance | Normal, reversed | 8 / passed each; 36 assertions each |
| Exact ZIP + AAI Loaders 0.2.11, lubricated | Normal, reversed | 11 / passed each; 59 assertions each |
| Exact ZIP + AAI Loaders 0.2.11, expensive | Normal, reversed | 9 / passed each; 42 assertions each |
| Exact ZIP, save/restart during active outage and upgrade marks | Normal | 1 / passed; 7 assertions, resumed through tick 1800 |

The archive trials use the real default **16 operations/tick**. Ordinary item and
equipment preservation, repeated outages, deconstruction/upgrade marks,
blueprint/force-build ghosts, scan repair and AAI fluid continuity pass.
A separate native 400-tick checkpoint preserves the active harness/world across
two localhost server processes. This is persistence evidence, not an old-version
upgrade fixture or a claim about arbitrary personal saves.

Named preset timing checks use **128 operations/tick** to isolate thresholds from
scheduler delay. Both build orders observe the following belt/underground/splitter
transition spreads in this bounded fixture:

| Preset | Power-down spread | Power-up spread |
| --- | --- | --- |
| Default | 16 ticks | 115 ticks |
| Synchronized | 0 ticks | 1 tick |
| Responsive | 0 ticks | 0 ticks |

Responsive switches off 9 ticks after the outage and restarts 2 ticks after power
returns here. These are fixture observations, not promises for every network or
polling budget. Custom mode separately verifies both states inside a 48%/72%
deadband and transitions below/above it, in both orders.

## Focused performance comparison

Five alternating before/after process pairs, each with a discarded warmup, native
Windows Lua 5.2.4 `os.clock()`, normal GC. Each measured sample covers 1000 ticks
and the same two threshold getters per entity check. Baseline is exported
`d056f21:modules/utils.lua`, using the same policy module and ordinary table inputs
on both sides. This isolates repeated resolution/cache cost; the real userdata
correctness fix is established by the native trials above.

| Checks/tick | Before median (observed range) | After median (observed range) |
| --- | --- | --- |
| 16 | 0.041 s (0.040–0.048) | 0.004 s (0.003–0.011) |
| 1024 | 2.346 s (2.315–2.461) | 0.309 s (0.280–0.328) |

These are whole-workload CPU totals, not one-tick latency or a whole-mod speedup.
They show no threshold-read regression and substantially less repeated work.
Production additionally obtains one configuration per belt check instead of
calling both wrapper getters. No claim is made about native API cost, all network
sizes, allocation peaks or guaranteed worst-case tick time. The repeatable workload
is `tests/performance_power_thresholds.lua`; raw paired samples stay ignored.

## Artifact identity and limits

Test ZIP SHA-256:
`a1b6f4f5c376f70a892fc596765f993a7fa41504ef0b7c39d4aad0cd6d769349`.
Its working manifest says **1.1.1**; these results identify tested bytes, not a
publication version or an uploadable 1.3.2 release. Rebuild and verify after
changing packaged metadata. Commands and profile distinctions: [README.md](README.md).

[Issue #11](https://github.com/PiotrKaszuba/PoweredBeltsExtended/issues/11) now
specifies Factorio 2.1. A valid synthetic floating-belt upgrade chain with a custom
collision mask passes clone assertions and native 2.0 loading. No general 2.0
clone defect was established, so no speculative compatibility patch was added.
This does not certify Dredgeworks or resolve the reporter's exact 2.1 setup.

Script-built/mined entities are valid engine tests of the shared event handlers;
this review found no distinct player/robot branch requiring synthetic duplication.
It does not claim actual construction-robot/player cursor coverage, all mod pairs,
Space Age behavior or a broad performance audit. Existing separately powered
underground endpoints and optional Dolly integration remain outside this change.

Detailed generated reports stay ignored under `tests/artifacts/review-2.0-*`.
Only this bounded summary is tracked; complete per-run logs are not repository docs.

## Final 1.3.2 artifact acceptance

27 October 2026. The correctly versioned ZIP has **20 files / 402012 bytes**,
SHA-256 `56081186e449e356bfc1e877856c1820f13ee95989892e00281f4fd21d604b10`.
Only `info.json` (1.3.2) and the changelog date differ from the earlier accepted
candidate; production Lua and all other packaged files are byte-identical.
ZIP CRCs, one mod-root directory, portable paths and source bytes pass inspection.

Fresh Factorio 2.0.77 runs of these exact bytes pass:

- Production base acceptance: eight scenarios / 36 assertions, normal build order.
- AAI Loaders 0.2.11 lubricated lifecycle: three scenarios / 23 assertions.
- Actual 1.3.1 → 1.3.2 configuration change during an outage: one scenario / seven
  assertions. A native checkpoint was created with production source `45babf3`
  reconstructed as a 1.3.1 ZIP (not a downloaded portal archive). After swapping to
  the final 1.3.2 ZIP, the engine reported old/new versions 1.3.1/1.3.2 at tick 401;
  the original scenario resumed through tick 1800 with planner/item checks intact.

The previous reversed-order, preset, expensive-AAI and paired CPU evidence remains
applicable to identical production code. New raw runs and the isolated upgrade
script/checkpoint are ignored under `tests/artifacts/release-1.3.2-*`.
