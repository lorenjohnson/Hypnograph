---
sidebarTitle: Installation
---

# Installation

The current Hypnograph beta is a direct macOS download for Apple Silicon Macs. Because Hypnograph is currently distributed this way during early development, macOS shows an extra security warning the first time you open it. This is part of Apple's normal protection for apps that are not yet distributed through Apple's standard beta or notarized channels.

**Current beta: v0.2.0 build 12, released May 18, 2026 for Apple Silicon macOS.**

## Steps

1. Download the current [Hypnograph beta DMG](https://github.com/lorenjohnson/Hypnograph/releases/download/v0.2.0-beta.12/Hypnograph-0.2.0-12-macOS-unsigned.dmg). The [GitHub release](https://github.com/lorenjohnson/Hypnograph/releases/tag/v0.2.0-beta.12) also includes a [ZIP archive](https://github.com/lorenjohnson/Hypnograph/releases/download/v0.2.0-beta.12/Hypnograph-0.2.0-12-macOS-unsigned.zip) and [SHA256 checksum](https://github.com/lorenjohnson/Hypnograph/releases/download/v0.2.0-beta.12/Hypnograph-0.2.0-12-macOS-unsigned.sha256).
2. Open the downloaded file, drag the Hypnograph icon into the `Applications` folder, and then open Hypnograph from `Applications`.
3. If macOS shows a warning with only `Move to Trash` or `Cancel`, choose `Cancel`.
4. Open `System Settings` > `Privacy & Security`.
5. Scroll down until you see the message about Hypnograph, then click `Open Anyway`.
6. Open Hypnograph again. macOS should show one more warning, this time with an `Open Anyway` option.
7. Click `Open Anyway`, then enter your password if macOS asks for it.
8. After that first approval flow, Hypnograph should open normally on subsequent launches, until you install a newer beta release and need to approve it once again.

You should only need to do this the first time you open a new beta release.

## Troubleshooting

### If Apple Photos Gets Stuck After Upgrading From An Older Beta

If you are coming from a much older Hypnograph beta and Apple Photos access seems stuck, loops strangely, or never settles after you click allow, use this recovery path:

1. Quit Hypnograph.
2. Open `System Settings` > `Privacy & Security` > `Photos`.
3. Find `Hypnograph` in that list and remove or disable its Photos access if macOS currently shows it there.
4. Open `Terminal` and run `tccutil reset Photos lorenjohnson.Hypnograph`.
5. Open the latest Hypnograph beta again from `Applications`.
6. When Hypnograph asks for Apple Photos access again, allow it.
7. If Hypnograph still looks like access is missing after that, quit it once more and relaunch it.

This should not normally be necessary on current betas. It is mainly a recovery step for earlier testers whose existing Apple Photos permission state may have been left in a bad place by older builds.

If you want Apple's own instructions as well, see [Open an app by overriding security settings](https://support.apple.com/en-afri/guide/mac-help/mh40617).

This extra setup is temporary. Hypnograph is expected to move to Apple's beta distribution platform soon, which should remove these extra steps. Thanks for your patience as an early tester. The upside, for now, is getting access to the app sooner.
