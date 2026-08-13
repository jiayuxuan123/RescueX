# RescueX v3.5.9-r1 -- update-transaction and false-rescue correction

This build preserves the v3.5.9 UI, transaction journal, exact recovery,
integrity checks, diagnostics, and optional native watchdog. It changes only the
unsafe update/restart boundary and the failure classification that amplified it.

## Fixed

- RescueX no longer moves, replays, removes, or reboots from Root manager update
  queues such as `modules_update`. Magisk, KernelSU, APatch, and their frontends
  remain the only owners of their own update transaction and restart policy.
- A changed `BOOT_TOKEN` is now observability and ownership evidence only; it is
  not sufficient by itself to count a previous `BOOTING` transaction as a boot
  failure. Normal manager-driven updates, OTA handoffs, and short user reboots
  therefore cannot directly enter the progressive/full-rescue path.
- Failure counting requires an explicit `FAILURE`/`TEST_FAILURE` state, or an
  incomplete prior boot with a valid RTC timestamp outside the configured user
  reboot grace period. Early boot with an unusable RTC stays fail-closed against
  automatic module changes.
- First-install `DRY_RUN=true` is retained and the installer output now matches
  that behavior. The native watchdog source also has portable fallback guards;
  Shell remains the default engine and automatic fallback.

## Intentional behavior retained

- An actual watchdog timeout still performs only verified disable-marker rescue,
  commits `RESCUED`, and requests one normal reboot after the durable commit.
- RescueX never deletes package-manager restrictions and does not restore any
  disable marker without a transaction journal that proves ownership.
- Existing installations keep their user configuration. To adopt the safest
  default watchdog path, set `WATCHDOG_ENGINE=shell` in WebUI if an older config
  had explicitly selected native.

## Validation

- POSIX shell syntax checks pass for all module scripts.
- JavaScript syntax checks pass for the WebUI controller.
- Native watchdog source compiles and passes `--self-test` in the available host
  compatibility build. The shipped arm64 Android binary remains optional and is
  selected only after its device-side self-test succeeds.
- Offline state-machine checks cover manager update staging, short manual reboot,
  early RTC/token transition, normal success, explicit failure, and prolonged
  incomplete boot.

## v3.5.9-r2 delta (2026-08-13)

- Fix boot statistics integrity: `compute_boot_stats` now clamps `SUCCESS` to
  `TOTAL` when duplicated `boot_history` entries made the success rate exceed
  100% (e.g. 7 successes over 4 recorded boots, previously shown as 175%).
- Repackaged cleanly: the earlier r1 archive accidentally contained an extra
  `Users/Administrator/.../handoff/common-r1.sh` path entry; it is removed.
- Version metadata bumped to v3.5.9-r2 / 35011 so devices already on v3.5.9-r1
  (35010) receive this update through the normal update channel.
