---
doc-status: draft
---

# Apple Developer Release Readiness

## Overview

Hypnograph needs a real Apple-facing release path instead of relying indefinitely on the current unsigned direct-download fallback. The intended outcome is to get the project into a state where signed macOS beta builds are possible, notarization is possible, and TestFlight can be evaluated or adopted once Apple Developer Program access is in place.

Right now, the main blocker is not build automation itself but account readiness. Apple Developer enrollment appears to be blocked on the current personal account, so a prerequisite task is establishing an alternate email/account path that can be used for Apple enrollment and related operational setup. The project should therefore treat release readiness as a combined operational-and-technical track: first unblock the account prerequisites, then define and implement the signed/notarized release flow.

This project also absorbs the forward-looking items that were previously parked in the archived unsigned-release project. Those items were always follow-up work rather than part of the unsigned-release implementation itself, so they belong here as first-class scope.

## Rules

- MUST define the path from the current unsigned beta release process to a signed and notarized macOS beta release process.
- MUST treat Apple Developer Program access as the main prerequisite blocker for signed releases and TestFlight usage.
- MUST document the alternate-email prerequisite clearly enough that account setup can happen outside the codebase without losing context.
- MUST preserve the current unsigned direct-download release flow as a fallback until the signed/notarized path is live and proven.
- SHOULD evaluate whether TestFlight for macOS is actually the desired beta channel once Apple enrollment is unblocked, rather than assuming it is required.
- SHOULD capture the current email-address options considered for Apple enrollment and related admin use, including Cloudflare Email Routing, ImprovMX, Purelymail, Fastmail, and a possible self-hosted mail service.
- SHOULD treat self-hosted mail as an explicit open question rather than an assumed solution, with deliverability, spam filtering, and operational overhead called out directly.
- MUST carry over the signed/notarized/TestFlight follow-up intent from the archived unsigned-release document into this project.
- MUST NOT turn this write-up into a full implementation plan for email infrastructure unless that becomes necessary to unblock the Apple enrollment path.

## Plan

- Smallest meaningful next slice: document the Apple enrollment blocker, record the email/account options still under consideration, and define the minimum release-readiness target as Developer ID signing plus notarization for direct downloads, with TestFlight as a follow-on decision once enrollment is resolved.
- Immediate acceptance check: a future operator reading only this project doc should understand why signed releases are currently blocked, what prerequisite decision is still open around the alternate email/account setup, and what release capabilities we want once Apple access is available.
- Follow-on slice: once Apple enrollment is unblocked, convert the current unsigned release reference into a dual-track model where unsigned remains fallback and a new signed/notarized beta path becomes the preferred direct-download release path.
- Later checkpoint: after signing/notarization is available, decide whether to also stand up TestFlight for macOS betas or keep direct download as the primary beta channel.

## Open Questions

- Which email path is the right operational fit for Apple enrollment and release administration: forwarding only, a lightweight hosted mailbox, or a self-hosted mail service?
- Whether a self-hosted mail setup is genuinely sufficient for this use case or creates avoidable deliverability and trust issues compared with a hosted email provider.
- Whether TestFlight should become the primary beta path once Apple enrollment succeeds, or whether signed/notarized direct downloads remain the better fit for Hypnograph.
