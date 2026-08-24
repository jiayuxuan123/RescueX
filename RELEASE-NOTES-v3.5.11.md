# RescueX v3.5.11

> Mobile navigation and OTA detection fixes. Candidate version `v3.5.11` / `versionCode 350204`.

RescueX is used on phones first, tablets second, so this release prioritizes
the Android WebUI behavior over desktop-shaped layout assumptions.

## Installer language is now consistent

The installer printed device information (SDK, model, manager) in Chinese from
hard-coded strings, but the WebUI volume-key prompt went through locale
detection and fell back to English. Recovery and installer environments often
expose no readable locale, so the same screen mixed Chinese and English right at
the only irreversible-looking choice.

- Chinese is now the default installer language. Only an explicitly non-Chinese
  locale selects English prose.
- Chinese locale variants (`zh-CN`, `zh-TW`, `zh-Hans`, `cmn`, `yue`) all resolve
  to Chinese.
- The three volume-key lines are always bilingual regardless of locale, so the
  choice cannot be misread:
  `[音量+] 安装 WebUI / Install WebUI`,
  `[音量-] 暂不安装 WebUI / Skip WebUI`,
  `60 秒无操作将安装 WebUI / No input in 60s: install`.
- Fallback strings used when `webui-choice.sh` is unavailable are Chinese too,
  so a missing helper cannot reintroduce mixed output.

## Monet dynamic color now reads the real system palette

The previous implementation read a single seed color and derived every tone from
it with an HSL approximation, so on a real device the result barely differed
from the static palette. It looked like the feature was doing nothing.

This is a Root module, so it can read what the system actually generated.
Android 12+ publishes the Material You tonal palettes as framework color
resources (`system_accent1_*`, `system_accent2_*`, `system_neutral1_*`,
`system_neutral2_*`), and `cmd overlay lookup` resolves them for the current
user. That command requires shell or root privileges, which the module already
has. New `monet-palette.sh` reads the 15 roles the WebUI needs and returns
resolved `#rrggbb` values, so MD3 uses the same colors as the system UI.

The reader is display-only. It never writes a setting, never enables, disables,
or fabricates an overlay, and never touches rescue state.

Degradation is explicit instead of silent:

- Real palette resolved: the appearance dialog reports "using the real system
  Material You palette".
- Only a theme seed color readable (older Android, or no `cmd overlay`): the
  seed approximation is used and labeled as an approximation.
- Nothing readable: Monet turns itself back off and the static MD3 palette
  stays, rather than pretending to be active.

## Fixed: mobile bottom navigation did not switch pages

The bottom navigation bar highlighted the tapped item but every card stayed on
screen, so the phone WebUI behaved like one long desktop page.

`script.js` toggles a `workspace-hidden` class on each group card, but the
matching CSS rule was missing from the shipped stylesheet, so nothing was ever
hidden. The rule is restored, and `hidden`-attribute handling for cards, the
status hero, and the overview quick actions is now explicit so a card cannot
reappear because another stylesheet declares a display value.

Verified: each of the five views now shows only its own group, in both the
MIUI X and Material Design 3 appearances.

## Fixed: OTA mode was permanently reported as an update signal

On a normally installed module the OTA state stayed stuck on an active vendor
update signal. Three causes:

- Persistent `ro.*` and `persist.*` vendor update properties survive reboots, so
  a device that finished an update long ago still looked like it was updating.
  Only volatile `sys.*` update state is trusted now.
- A running `update_engine` was treated as a signal. On A/B devices it is a
  normal always-present system service, so this alone pinned the module to the
  long OTA timeout on every boot. That check is removed.
- Vendor status files were accepted without a recency check, so a stale status
  file extended the boot timeout indefinitely. Every marker now requires a
  recent modification time.

The same stale-marker problem existed in the independent patch-update detector
in `common.sh` (permanent `/data/oplus/ota/update_status`, an always-present
`ota_package` directory, and non-volatile properties). It now requires an
active state plus a recent timestamp, and vendor staging directories only count
when they hold a recent payload.

The user-visible label is now the neutral "vendor update signal" instead of a
ColorOS-specific one, since the checks cover OPlus, MIUI, and vivo paths.

Detection priority is unchanged: manual guard, build baseline, vendor signal,
then the legacy compatibility signal. OTA detection still only selects a boot
timeout. It does not change failure counts, the watchdog, module disable and
restore, rescue transactions, or reboot behavior.

## Removed: ColorOS feature extension

The 30-item ColorOS optimizer catalog was unrelated to automatic bootloop
rescue and made the module's purpose incoherent. Removed entirely:
`coloros-compat.sh`, the WebUI card and its i18n, the action registrations, the
boot-time auto-apply hook in `service.sh`, the install permission, the
integrity manifest entry, and the dedicated test file.

Only the rescue-relevant part is kept: vendor OTA and patch-update detection,
which exists solely to pick a safer boot timeout during a system update.

## WebUI appearance and installation preference

- A confirmed WebUI install preference survives upgrades, so ordinary updates
  no longer depend on volume-key input, and an accidental volume-down press
  cannot delete an existing WebUI.
- MIUI X remains the default appearance. Material Design 3 is selectable, with
  optional Monet dynamic color scoped to MD3.
- The appearance entry is a plain text button next to the title that opens the
  chooser; it never switches a theme directly.

## Other phone-first corrections

- The status refresh action stays in the app bar on every view. It was hidden
  below 520px, where the overview quick actions are also hidden, leaving no way
  to refresh from the other four views.
- Language buttons and checkbox rows now meet a 36px and 44px touch target.
- The update notice card moved from rescue actions to logs and reports, so the
  rescue view holds only actual rescue operations.

## Validation

Offline verification for this candidate:

- OTA detection: 16 cases, including a regression test asserting that stale and
  persistent vendor signals are ignored.
- Monet palette: 7 cases against a stubbed `cmd overlay lookup`, covering
  palette preference, alpha stripping, labeled seed fallback, fail-closed with
  no readable source, vendor property seeds, and a static check that the reader
  performs no writes.
- WebUI choice: 7 cases, including Chinese as the default for an unreadable
  locale, Chinese variant handling, English prose for foreign locales, and an
  assertion that the volume-key lines stay bilingual in every language.
- Persistence: 3 cases. Release metadata: 1 case.
- All Shell scripts pass `sh -n`; `webroot/script.js` passes `node --check`.
- WebUI checked in an offline preview with a mock bridge: per-view card
  isolation in both themes, real-palette and seed-fallback Monet paths in light
  and dark, no horizontal overflow at 320/360/390/480/768px, no sub-36px touch
  targets, and no bottom-bar occlusion of the last card.

## Required device validation before release

Offline checks cannot confirm host bridge or real OTA behavior. Before
publishing, verify on hardware:

1. Bottom navigation, appearance chooser, and Monet in KernelSU, APatch, MMRL,
   and KsuWebUIStandalone or a compatible Magisk host. For Monet specifically,
   confirm the appearance dialog reports the real system palette and that the
   colors follow a wallpaper or theme change after a refresh.
2. OTA state on an idle device across several reboots, confirming it no longer
   reports an active update.
3. A real vendor OTA (download, verify, reboot install, A/B slot switch),
   confirming the longer timeout is selected during the update and released
   afterwards.
4. Rescue behavior is unchanged: failure counting, module disable and restore,
   watchdog trigger, and reboot flow.
