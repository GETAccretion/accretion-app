# Accretion app

The iPhone app for [Accretion](https://getaccretion.app): browse the Accretion store, then sign and install apps on your device with your own certificate. The current version is listed in [`app-repo.json`](../app-repo.json).

Accretion is a fork of [Feather](https://github.com/claration/Feather) by claration, and is licensed under GPL-3.0 like Feather. Feather's original README follows below the line for reference; its Download section is about Feather itself, not Accretion.

## Get Accretion

- **From the store:** sign in on the website, then open the [Accretion app page](https://getaccretion.app/#/app/io.github.getaccretion.Accretion). Downloads from the store need an Accretion account.
- **GitHub releases** carry release notes only. There's no `.ipa` attached.
- **First install** with the signer from your certificate seller, Sideloadly, AltStore or SideStore. After that, the app tells you when a new version is out.

## What Accretion adds to Feather

### Identity and links
- **Its own app:** own name, icon and bundle ID (`io.github.getaccretion.Accretion`), so it installs next to Feather. Version numbering started at 1.0.0.
- **Its own link format, `accretion://`**, used by the Accretion web store's Install button. It only registers `accretion://`, so it never fights Feather over `feather://` links.
  - `accretion://install/<https link to .ipa>`
  - `accretion://source/<https link to source>`
  - `accretion://import-certificate?p12=…&mobileprovision=…&password=…` (same format as Feather)
- **Recommended sources:** Accretion Core, the full Accretion list and Accretion Mods come first.
- **"Made by Accretion"** on the Sources tab lists every Accretion Mod across your sources. Mods (bundle IDs under `io.github.accretionmods.`) are labelled "Accretion Mod" wherever apps are listed.

### Discover (the store in the app)
- **Discover is the first tab** and mirrors the web store:
  - **top bar:** Sign in / Account, Add source, search, and Discover · Saved · Feed · ♥;
  - **hero** with four stats: apps, sources, updated in the last 7 days, new in the last 30 days;
  - **shelves**, with "See all" where there's more: Most popular, Made by Accretion, Updates for your saved apps, Fresh today, New this month, From Accretion Core, Games, Utilities;
  - **All apps** with category chips (each with its count), a filter for apps that run on this iOS version, and Sort: Recently updated, Most popular, Newest apps, Name A–Z, Largest.
- **Search** lists names that start with what you typed first.

### App pages
- **Same layout as the web store's app page:**
  - **Install**, **Download IPA**, and the other installers: LiveContainer, Feather, AltStore, SideStore, TrollStore;
  - **Save**, **Share** and **Copy IPA link**;
  - likes and star ratings;
  - facts (version, build, release date, size, minimum iOS, category), What's new, screenshots, About, Versions and Permissions;
  - related shelves (more from the same developer, more in the same category), Info, and comments.

### Accretion account
- **The same account as the website.** Sign in with email, or Continue with Google, GitHub or Discord. Those open an in-app sign-in sheet and come back to the app with a one-time code (PKCE).
- **Downloads from the store need an account.** Install, Download IPA and the other installers ask you to sign in first.
- **Certificate backups:** your certificates can be backed up to your account. Each one is encrypted on the iPhone with a passphrase you choose (AES-GCM, key from PBKDF2) before it's uploaded, and restored the same way.
- **Accretion's own builds** (this app and Accretion Mods) are served privately by the store's download server, only to signed-in users and to personal source links.
- **Minimum supported version:** the store's `app-config.json` sets the oldest version that may still be used. Older copies show a full-screen "Update required" until they're updated. Copies older than 1.0.5 only see the update in the store.

### Certificates
- **Single-app profiles are understood.** Profiles that cover one App ID set the bundle ID automatically, and the signing screen says which installed app will be replaced. Prefix wildcards (`com.example.*`) adapt bundle IDs that don't fit.
- **App extensions with a single-app certificate:** extensions can't be signed for a one-app profile, so they're left out automatically and the pre-sign check lists which ones.
- **Several profiles per certificate.** Add extra profiles under certificate details → Profiles; each app gets its own: a wildcard first, then the one already assigned, then a free one. Single-App-ID certificates can then keep several apps installed and update each in place.
- **Revocation re-checks.** The selected certificate is re-checked automatically (at most hourly). You get one warning when it's revoked, and the flag clears when OCSP says it's good again.
- **Selection stays put.** Importing or deleting a certificate no longer changes which one is selected.
- **Development certificates** are labelled "Development".

### Signing
- **Preflight checks before signing**, each with a plain explanation:
  - **blocks signing:** revoked or expired certificate, expired profile, or an App Store-encrypted (FairPlay) app;
  - **warns, with "Sign Anyway":** encrypted extensions, or a minimum iOS newer than the device.
- **Recipes:** each app's name, icon, injected tweaks and properties are saved under `Documents/Recipes/<original bundle ID>/` and reapplied on every re-sign and update. Control it with "Remember for This App" while signing; Library shows "Recipe" on those apps and offers "Forget Recipe".
- **Tweak library:** the signing screen's Tweaks page shows "Suggested for This App" from [`tweaks.json`](https://github.com/AccretionMods/mods/blob/main/tweaks.json). One tap downloads a tweak (and anything it needs) from its own project, and it's kept in the recipe. The full catalog is in Settings → Signing → Tweak Library.
- **Readable install errors:** common iOS failures are explained, with the raw details underneath.

### Inject Tweaks
- **Library ✨ → Inject Tweaks** puts tweaks into an app in one screen:
  1. pick a decrypted IPA you own, from Files or from Library;
  2. add `.deb` or `.dylib` tweaks, from Files or from the tweak library;
  3. options: name on the Home Screen, install next to the original, use ElleKit, remember for updates;
  4. **Sign & Install** with your certificate, or **Export modded IPA** (unsigned) for another signer.
- **Encrypted App Store copies are rejected**, since they won't run after injection.

### Updates
- **Updates from Accretion's catalogs:** if an app's own source has nothing newer, Accretion's own catalogs (the store lists, Accretion Mods and the Accretion app source, including personal copies of them) are checked for the same bundle ID. Other sources only update their own apps. The newest higher version wins; there are no downgrades. These updates are never installed automatically, and the alert names the source they come from.
- **Automatic checks** at launch and whenever the app returns to the front (at most hourly), with a count badge on the Library tab and one "Updates available" alert per new version.
- **Settings → Installing** has "Check for Updates Automatically" and "Update Apps Automatically".
- **Update and Install:** one tap downloads, signs with the app's recipe and opens the install screen.
- **Updates in place:**
  - **Same app on the device:** the new version keeps the installed copy's bundle ID and certificate team, so iOS replaces the app and keeps its data.
  - **Different certificate team:** the update is refused with an explanation instead of creating a copy.
  - **One Library entry per app:** the new download and the new signed copy replace the old ones.
- **Library ✨ menu:**
  - **Update All** updates every app with an update.
  - **Re-sign All** re-signs every app with the selected certificate after a revocation or replacement, keeping recipes, and lists any apps iOS needs deleted first.
  - **Inject Tweaks** (see above).
  - A progress banner shows at the bottom of Library while Update All or Re-sign All runs.

### LiveContainer
- **Store and source app pages:** the LiveContainer button sends the IPA link to LiveContainer (`livecontainer://install?url=…`), which runs many apps under one signature. That's a way around single-App-ID certificates.
- **Library apps:** "Open in LiveContainer…" packs the IPA and opens the share sheet.

### Look
- **Store colours and fonts across the app:** the tab bar, Settings pages and signing pages use the web store's look.
- **Confirmations before deleting** apps, sources, certificates and backups.
- **Empty states work on iOS 16.**

### Building and releasing
- **iPhone only.** There's no Mac Catalyst build.
- **Every push to `main` builds** `Accretion.ipa` to check it compiles. No build artifacts are kept.
- **Tags named `accretion-v*`** upload the `.ipa` to the store's private storage (using the `ACCRETION_UPLOAD_KEY` secret), create a release with notes only, and point `app-repo.json` (the app's own source) at the download server.
- **The build resolves Swift packages first, with retries,** to get past an intermittent Xcode 26 crash.

### Where the code lives
Accretion code sits in its own files where possible, so merging Feather updates stays manageable:
- `Feather/Backend/Signing/`: `CertificateSlots`, `Preflight`, `RecipeStore`, `AutoSignPipeline`, `ProfileStore`, `TweakCatalog`, `LiveContainer`
- `Feather/Backend/Store/StoreService.swift`
- `Feather/Backend/Account/`: `AccretionAccount`, `AppPolicy`
- `Feather/Backend/Observable/UpdateManager+Accretion.swift`
- `Feather/Views/Accretion/`: `Theme`, `Discover`, `Settings`, `Inject`, `Update`
- `Feather/Views/Signing/Tweaks/`, `Feather/Views/Sources/Accretion/`
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
