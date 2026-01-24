# Beta Release / TestFlight

**Status:** Planning
**Created:** 2026-01-24

## Overview

Prepare Hypnograph for first external beta via TestFlight: Developer Program enrollment, App Store Connect setup, app identity, and tester recruitment.

## Open Questions

- [live-mode-feature-flag](live-mode-feature-flag.md) — Should Live Mode be gated before beta?
- [in-app-feedback](in-app-feedback.md) — Include feedback mechanism in beta?
- Product website? — Useful for privacy policy URL, app context, but may not be required
- Bundle ID / Developer Entity — Considering "Sketch" as entity name but haven't started business yet
- Privacy policy — TestFlight may require URL; verify no analytics/telemetry in app
- Entitlements — App Sandbox, Hardened Runtime, file access, camera/mic?

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
