# Accretion app

The iPhone app for [Accretion](https://getaccretion.github.io): sign and install apps on your device with your own certificate, straight from the Accretion store.

Accretion is a fork of [Feather](https://github.com/claration/Feather) by claration, and is licensed under GPL-3.0 like Feather. Everything below this section is Feather's original README and still applies.

## What Accretion adds to Feather

### Identity and store
- **Its own app:** own name, icon and bundle ID (`io.github.getaccretion.Accretion`), so it installs next to Feather. Version numbering starts at 1.0.0.
- **Its own link format, `accretion://`**, used by the Accretion web store's Install button. It only registers `accretion://`, so it never fights Feather over `feather://` links.
  - `accretion://install/<https link to .ipa>`
  - `accretion://source/<https link to source>`
  - `accretion://import-certificate?p12=…&mobileprovision=…&password=…` (same format as Feather)
- **Recommended sources:** Accretion Core, the full Accretion list and Accretion Mods come first.
- **"Made by Accretion"** on the Sources tab lists every Accretion Mod across your sources. Mods (bundle IDs under `io.github.accretionmods.`) are labelled "Accretion Mod" wherever apps are listed.
- **Settings → Accretion** has the automatic update check switch, the Tweak Library, and links to the web store, the signing guide and the mods repo.

### Certificates
- **Single-app profiles are understood.** Profiles that cover one App ID set the bundle ID automatically, and the signing screen says which installed app will be replaced. Prefix wildcards (`com.example.*`) adapt bundle IDs that don't fit.
- **Several profiles per certificate.** Add extra profiles under certificate details → Profiles; each app gets its own: a wildcard first, then the one already assigned, then a free one. Single-App-ID certificates can then keep several apps installed and update each in place.
- **Selection stays put.** Importing or deleting a certificate no longer changes which one is selected.
- **Revocation re-checks.** The selected certificate is re-checked automatically (at most hourly). You get one warning when it's revoked, and the flag clears when OCSP says it's good again.

### Signing
- **Preflight checks before signing**, each with a plain explanation:
  - **blocks signing:** revoked or expired certificate, expired profile, or an App Store-encrypted (FairPlay) app;
  - **warns, with "Sign Anyway":** encrypted extensions, or a minimum iOS newer than the device.
- **Recipes:** each app's name, icon, injected tweaks and properties are saved under `Documents/Recipes/<original bundle ID>/` and reapplied on every re-sign and update. Control it with "Remember for This App" while signing; Library shows "Recipe" on those apps and offers "Forget Recipe".
- **Tweak library:** the signing screen's Tweaks page shows "Suggested for This App" from [`tweaks.json`](https://github.com/AccretionMods/mods/blob/main/tweaks.json). One tap downloads a tweak (and anything it needs) from its own project, and it's kept in the recipe. The full catalog is in Settings → Accretion → Tweak Library.
- **Readable install errors:** common iOS failures are explained, with the raw details underneath.

### Updates
- **Updates from every source:** if an app's own source has nothing newer, every other source is checked for the same bundle ID. The newest higher version wins; there are no downgrades.
- **Automatic checks** at launch and whenever the app returns to the front (at most hourly), with a count badge on the Library tab and one "Updates available" alert per new version.
- **Update and Install:** one tap downloads, signs with the app's recipe and opens the install screen.
- **Updates in place:**
  - **Same app on the device:** the new version keeps the installed copy's bundle ID and certificate, so iOS replaces the app and keeps its data.
  - **Different certificate team:** the update is refused with an explanation instead of creating a copy.
  - **One Library entry per app:** the new download and the new signed copy replace the old ones.
- **Library ✨ menu:**
  - **Update All** updates every app with an update.
  - **Re-sign All** re-signs every app with the selected certificate after a revocation or replacement, keeping recipes, and lists any apps iOS needs deleted first.
  - A progress banner shows at the bottom of Library while either runs.

### LiveContainer
- **Source app pages:** a 📦 button sends the IPA link to LiveContainer (`livecontainer://install?url=…`), which runs many apps under one signature. That's a way around single-App-ID certificates.
- **Library apps:** "Open in LiveContainer…" packs the IPA and opens the share sheet.

### Building and releasing
- **Every push to `main` builds** `Accretion.ipa` and the Mac Catalyst zip (Actions → Release → artifact).
- **Tags named `accretion-v*`** publish a release and point `app-repo.json` (the app's own source) at it.
- **The build sets up Swift packages first, with retries,** to get past an intermittent Xcode 26 crash.

### Where the code lives
Accretion code sits in its own files where possible, so merging Feather updates stays manageable:
- `Feather/Backend/Signing/`: `CertificateSlots`, `Preflight`, `RecipeStore`, `AutoSignPipeline`, `ProfileStore`, `TweakCatalog`, `LiveContainer`
- `Feather/Backend/Observable/UpdateManager+Accretion.swift`
- `Feather/Views/Sources/Accretion/`, `Feather/Views/Signing/Tweaks/`
- `Feather/Views/Settings/Certificates/Info/CertificateProfilesSection.swift`

Changes inside Feather's own files are marked `// Accretion:`.

**Pulling in Feather updates:** `git fetch upstream && git merge upstream/main`, then fix any conflicts in the `// Accretion:` blocks.

---

[![GitHub License](https://img.shields.io/github/license/claration/Feather?color=%23C96FAD)](https://github.com/claration/Feather/blob/main/LICENSE)
[![Sponsor Feather](https://img.shields.io/static/v1?label=Sponsor%20Feather&message=%E2%9D%A4&logo=GitHub&color=%23fe8e86)](https://github.com/sponsors/khcrysalis)

<div align="center">

<img title="Feather" alt="Feather" height="180" src="landing.png">

Sideloading app meant for developer certificates.

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="demo-dark.png"><source media="(prefers-color-scheme: light)" srcset="demo-light.png"><img alt="Feather" src="demo-light.png"></picture></p>


</div>

## Features

- User friendly, and clean UI.
- Sign and install applications.
- Supports [AltStore](https://faq.altstore.io/distribute-your-apps/make-a-source#apps) repositories.
- View detailed information about apps and your certificates.
- Configurable signing options mainly for modifying the app, such as appearance and allowing support for the files app.
  - This includes patching apps for compatibility and Liquid Glass.
- Tweak support for advanced users, using [Ellekit](https://github.com/tealbathingsuit/ellekit) for injection. 
  - Supports injecting `.deb` and `.dylib` files.
- Actively maintained: always ensuring most apps get installed properly.
- No tracking or analytics, ensuring user privacy.
- Of course, open source and free.

## Download

Visit [releases](https://github.com/claration/Feather/releases) and get the latest `.ipa`.

<a href="https://celloserenity.github.io/altdirect/?url=https://raw.githubusercontent.com/claration/Feather/refs/heads/main/app-repo.json" target="_blank">
   <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
</a>
<a href="https://github.com/claration/Feather/releases/latest/download/Feather.ipa" target="_blank">
   <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="200">
</a>

## Translating

Feather now has translation support, all localizations are located in `Feather/Resources/Localizable.xcstrings`.

To add a new language, open Xcode and use the interface to add/contribute to languages.

To properly contribute and test potentially test localizations, you can head over to the [contributing guide](./CONTRIBUTING.md).

## Sponsors

| Thanks to all my [sponsors](https://github.com/sponsors/claration)!! |
|:--------------------------------------------------------------------:|
| <img src="https://sponsors.claration.dev/sponsors.png">              |
| _**"samara is cute" - Vendicated**_                                  |

## Acknowledgements

- [Samara](https://github.com/claration) - The maker
- [idevice](https://github.com/jkcoxson/idevice) - Backend for builds with this included, used for communication with `installd`.
- [*.backloop.dev](https://backloop.dev/) - localhost with public CA signed SSL certificate
- [Vapor](https://github.com/vapor/vapor) - A server-side Swift HTTP web framework.
- [Zsign](https://github.com/zhlynn/zsign) - Allowing to sign on-device, reimplimented to work on other platforms such as iOS.
- [LiveContainer](https://github.com/LiveContainer/LiveContainer) - Fixes/some help
- [Nuke](https://github.com/kean/Nuke) - Image caching.
- [Asspp](https://github.com/Lakr233/Asspp) - Some code for setting up the http server.
- [plistserver](https://github.com/nekohaxx/plistserver) - Hosted on https://api.palera.in.

## License 

This project is licensed under the GPL-3.0 license. You can see the full details of the license [here](https://github.com/claration/Feather/blob/main/LICENSE). It's under this specific license because I wanted to make a project that is transparent to the user thats related to certificate paired sideloading, before this project there weren't any open source projects that filled in this gap.

By contributing to this project, you agree to license your code under the GPL-3.0 license as well (including agreeing to license exceptions), ensuring that your work, like all other contributions, remains freely accessible and open.
