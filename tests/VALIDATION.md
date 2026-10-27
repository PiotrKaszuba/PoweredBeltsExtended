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
