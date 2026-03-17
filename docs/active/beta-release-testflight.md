# Beta Release / TestFlight

**Status:** Planning
**Created:** 2026-01-24

## Overview

Prepare Hypnograph for first external beta via TestFlight: Developer Program enrollment, App Store Connect setup, app identity, and tester recruitment.

## Current Enrollment Blocker (2026-03-17)

- Apple Developer Program enrollment is currently blocked by Apple fraud-control checks on the current account application.
- TestFlight path is therefore blocked until enrollment is resolved.
- Next attempted step: open a new Apple Developer account application using a different email address.

## Open Questions

- [live-mode-feature-flag](live-mode-feature-flag.md) — Should Live Mode be gated before beta?
- [in-app-feedback](in-app-feedback.md) — Include feedback mechanism in beta?
- Product website? — Useful for privacy policy URL, app context, but may not be required
- Bundle ID / Developer Entity — Considering "Sketch" as entity name but haven't started business yet
- Privacy policy — TestFlight may require URL; verify no analytics/telemetry in app
- Entitlements — App Sandbox, Hardened Runtime, file access, camera/mic?
- Optimized Photos storage — can we detect local-vs-iCloud assets before playback?

### Optimized Photos storage note (resolved)

PhotoKit does not expose a simple `PHAsset` property like `isLocallyAvailable`.
However, we can infer availability safely by probing with network access disabled and
checking result metadata/errors (`PHImageResultIsInCloudKey`, network-access-required
errors). This is now partially implemented in-core:

- warm a local-availability cache for recent video identifiers
- prefer known-local videos during random clip selection
- still fall back to cloud-backed assets when needed

This reduces initial black/blank clips on libraries using Optimize Mac Storage, while
keeping current behavior as fallback.

Current rollout safety:
- Feature is gated behind `HYPNO_ENABLE_PHOTOS_LOCAL_PREF=1`
- Default is OFF, so baseline beta behavior is unchanged unless explicitly enabled
- Beta override is exposed in app Settings: "Prefer Locally Available Photos Videos (Beta)"

## Test Coverage Snapshot (2026-02-17)

Automated (`HypnoCoreTests`):
- No local videos: all known-cloud assets classified as cloud tier.
- Few local / many remote: local vs unknown vs cloud tier counts are modeled and asserted.
- Feature disabled: prioritization behaves neutrally (no tiering impact).
- No Photos access: post-auth coordinator does not force-enable Photos sources.
- Authorized + empty library + Photos available: coordinator forces `photos:all` as expected.
- PhotoKit metadata inference: in-cloud and network-required signals map to cloud-tier.

Not covered by automation yet:
- End-to-end iCloud download timing/latency on real optimized-storage libraries.
- Real disk-growth behavior when many cloud assets are eventually played/downloaded.
- Concurrent playback under heavy remote-only libraries (stress/perf behavior).

Manual beta checks still required:
- Test machine with Optimize Mac Storage + mostly remote videos.
- Watch initial playback delays with prioritization OFF vs ON.
- Observe Photos/iCloud storage growth over a 10-20 minute playback session.
- Confirm behavior when Photos permission is denied, then granted later.

## Readiness Snapshot (2026-02-17)

### Good enough for friend beta now

- Core app is usable with Photos optimized storage, with some startup/download delay.
- Recent change (when feature flag enabled): source selection prefers videos known to be local first.
- Acceptable to proceed with friend beta if we include a short in-app/README disclaimer:
  - first-use playback may pause while Photos downloads iCloud media
  - this may temporarily use additional disk space

### Likely blockers before broader external TestFlight

- App Sandbox is not yet enabled for Hypnograph target.
- Folder-source model currently stores raw paths; sandbox-safe persistence likely needs
  security-scoped bookmarks (or beta scope reduced to Photos-only first).
- Legacy fallback path scans `~/Pictures/Photos Library.photoslibrary/originals`, which is
  brittle and should not be primary behavior for App Store distribution.
- Need a stable privacy policy URL for App Store Connect metadata.

## Representational Page (MVP)

Goal: one trustworthy page to orient friends/testers and satisfy metadata needs.

- [ ] Public page with: what Hypnograph is, current beta status, and core workflow
- [ ] Privacy policy page (linked from representational page)
- [ ] TestFlight interest CTA (email / simple form)
- [ ] “Known beta limitations” section including Optimize Mac Storage behavior
- [ ] Support/contact section for feedback and bug reports

## Plan

### Phase 1: Apple Developer Program

- [ ] Enroll at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll) ($99/year)
- [ ] Complete identity verification
- [ ] Accept agreements in App Store Connect

### Phase 2: App Identity

- [ ] Finalize app icon (1024x1024 master → generate all sizes)
- [ ] Confirm bundle identifier
- [ ] Set marketing version and build number scheme

### Phase 3: Signing & Provisioning

- [ ] Create App ID in Developer portal
- [ ] Create distribution certificates
- [ ] Create provisioning profile for TestFlight
- [ ] Configure Xcode signing settings

### Phase 4: App Store Connect

- [ ] Create app record (name, bundle ID, language)
- [ ] Configure privacy disclosures
- [ ] Set up TestFlight info (description, feedback email, What to Test)

### Phase 5: Build & Upload

- [ ] Archive in Xcode, validate, upload
- [ ] Verify: launches, core features work, no debug features exposed

### Phase 6: TestFlight Groups

- [ ] Add internal testers (immediate access)
- [ ] Create external group and submit for Beta App Review

### Phase 7: Tester Recruitment

- [ ] Gather Apple ID emails for each tester
- [ ] Send invitation emails
- [ ] Set up feedback channel

**Testers** (need Apple ID email):

| Name              | Apple ID Email |
| ----------------- | -------------- |
| Robbie            |                |
| Lea               |                |
| Matt              |                |
| Santiago          |                |
| Darja             |                |
| Prokop            |                |
| Eli               |                |
| Jesse             |                |
| Cole              |                |
| John              |                |
| Elijah (Lije)     |                |
| Jonathan Haidle ? |                |
| Station           |                |
| Ben Cleek         |                |
| Beth              |                |

### Invitation Email Draft

```text
Subject: Hypnograph Beta — You're Invited

Hey [Name],

I've been building something I'd love your eyes on.

Hypnograph is a macOS app for creating layered video montages from your photo/video
library. Think of it as a visual instrument — you load clips, layer them with blend
modes and effects, and let them play together. It's part creative tool, part
meditation, part rediscovery of your own footage.

I'm getting ready for a first public release and would really value your feedback
as a beta tester.

**What testing involves:**
- Install via TestFlight (Apple's beta platform)
- Use the app however feels natural
- Let me know what's confusing, broken, or missing
- Crash reports are collected automatically (no action needed)

**To join:**
I'll need the email associated with your Apple ID so I can send you an invite
through TestFlight. Just reply with that and I'll add you.

No pressure to be thorough or formal — even just "this felt weird" or "I couldn't
figure out X" is helpful.

Thanks for considering it.

[Your name]
```
