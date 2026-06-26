# TikoHD — TikTok 1080p60 HD Upload Tweak (iOS)

Forces TikTok to publish in **true 1080p60 HD** instead of the on-device 540p30 re-encode.
This is a clean, minimal, **own-it** replica of BHTikTok++'s "Upload HD" — no telemetry,
no ban-shield, no fake-stats, no downloader. Just the HD mechanism, improved.

## What it does

| Layer | What | Default | Risk |
|---|---|---|---|
| **1 — HD flag** | Hooks `ACCCreationPublishAction` → forces `is_open_hd` / `is_have_hd = YES` (the exact, proven BHTikTok mechanism). Marks the post HD-eligible so TikTok's own pipeline builds the premium `bytevc1` 1080p60 rung at ingest. | **ON** | Very low (battle-tested) |
| **2 — HD export (beta)** | Hooks `AVAssetExportSession` → when TikTok picks a 540p/low preset for an imported clip, substitutes `HEVCHighestQuality` so the master is never downscaled on-device. | **OFF** | Medium — opt-in, test first |

A **two-finger hold (~0.8s)** anywhere opens the Tiko panel to toggle both. A cyan toast
confirms each time HD is forced (BHTikTok is silent — this isn't).

## Build (no Mac needed)

1. Create a new GitHub repo, push this folder (`TikoHD-Tweak/`) to it.
2. The included **GitHub Action** (`.github/workflows/build.yml`) compiles automatically on push.
   Open the **Actions** tab → latest run → **Artifacts** → download `TikoHD` (contains `TikoHD.dylib` + a `.deb`).
   - Or trigger manually: Actions → "Build TikoHD" → **Run workflow**.

*(Local alternative: install [Theos](https://theos.dev), then `make package FINALPACKAGE=1`.)*

## Inject into a stock TikTok IPA

You need a **clean, unmodified TikTok IPA** (the same version family you'll run; this targets the
34.x line). Then inject `TikoHD.dylib` — pick whichever tool you already use:

- **cyan / pyzule** (Linux / WSL / macOS):
  ```
  cyan -i TikTok.ipa -o TikTokHD.ipa -f TikoHD.dylib -s
  ```
  (`-s` bundles CydiaSubstrate, which the tweak needs.)
- **eSign / Scarlet** (on-device): import the IPA → **Inject dylib** → add `TikoHD.dylib` → re-sign.
- **Azule** (bash): `azule -i TikTok.ipa -o TikTokHD -f TikoHD.dylib`

This is the same flow that produced your current modded IPA — just with *our* dylib.

## Install

- **TrollStore** (best, if your iOS supports it): permanent signature, no cert, no 7-day expiry.
- **AltStore / SideStore**: free Apple ID = re-sign weekly; paid dev account ≈ 1 year.
- **eSign** with an enterprise/personal cert: works, but the cert can be **revoked** at any time.

## Use & verify

1. HD is **on by default**. Open the TikTok upload flow normally.
2. **Proof test** (your own method): post a 1080p60 master **direct-public**, let it get a few views
   (TikTok builds the HD rung lazily), then:
   ```
   yt-dlp -F "https://www.tiktok.com/@you/video/<id>"
   ```
   **Pass = a `bytevc1_1080p_60` row appears.** Control: the same master via the official API shows only `h264_540p`.
3. If imported/gallery clips still come out soft, open the panel (two-finger hold) and enable **Force HD export (beta)**, then re-test.

## Longevity / troubleshooting

- **Silently back to 540p after a TikTok app update?** The hook is pinned to the class/selector names
  (`ACCCreationPublishAction`, `is_open_hd`). If TikTok refactors them, the hook no-ops with no error.
  Re-verify the selectors against the new build before rebuilding.
- **App won't open / "untrusted":** cert expired or revoked → re-sign / refresh.
- **Export fails with HD-export beta on:** turn it off in the panel (some sources can't take the HEVC-highest path).

## Notes & honesty

- Layer 1 = exactly what your working IPA already does, so it's at least as reliable.
- Layer 2 and the deeper fps/bitrate hooks (`VEFPSCalculator`, `_video_bitrate_limit_rate`) are **not** shipped
  on-by-default because their selector signatures need on-device class-dump verification first — adding them
  blind risks crashing the publish flow. They're documented as the next step once Layer 1+2 are verified on your device.
- Running your real account on any modded binary carries a ban risk. Test on a throwaway first.
