# Direct Download Unsigned macOS Release

**Status:** Active
**Created:** 2026-03-17

## Why this exists

Hypnograph beta distribution is currently blocked on Apple Developer Program enrollment.
Until enrollment completes, we need a direct-download install path that is realistic for
friend testers on macOS.

## Constraints

- No TestFlight access without paid Apple Developer Program enrollment.
- No notarization without Apple Developer Program enrollment.
- Gatekeeper warning is expected for unsigned/unnotarized builds.

## Delivery format

- Primary artifact: `.dmg` (drag-and-drop install UX)
- Secondary artifact: `.zip` (fallback)
- Integrity artifact: `.sha256` checksums for both files

## Implemented automation

- Script: `scripts/release-macos-unsigned.sh`
- Behavior:
  - archives the `Hypnograph` scheme in `Release`
  - disables code signing during archive
  - builds DMG + ZIP artifacts
  - writes SHA-256 checksums
  - outputs to `dist/`

## Release operator checklist

1. From repo root, run `./scripts/release-macos-unsigned.sh`.
2. Verify artifacts exist in `dist/`.
3. Upload `.dmg`, `.zip`, `.sha256` to website or GitHub Release.
4. Include first-launch instructions in release notes:
   - open DMG
   - drag app to Applications
   - first launch via right-click `Open`

## Tester-facing copy (short)

Hypnograph currently ships as a direct macOS download while Apple beta channels are being
set up. macOS may show a warning on first launch. To continue safely, move the app to
Applications, then right-click the app and choose `Open` once.

## Follow-up after enrollment

- Keep this direct-download path as fallback for private builds.
- Add signed/notarized release flow once Developer Program access is active.
- Re-evaluate migration to TestFlight for wider beta.
