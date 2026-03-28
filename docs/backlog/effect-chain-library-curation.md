---
doc-status: draft
---

# Effect Chain Library Curation

## Overview

This project is separate from the effects UX spike. Its purpose is to review and improve the actual packaged set of effect chains, and possibly the underlying effect set, so the built-in library feels more coherent, intentional, and worth using.

Right now there is already a note to refine the packaged Effect Chains Library entries, and that likely belongs to a broader curation pass rather than to a UI refactor. The questions here are about what should ship, what should be renamed or reorganized, what feels redundant or weak, and whether any underlying effects should also be reconsidered as part of that pass.

This is a spike for now because it needs taste, selection, and criteria more than immediate implementation detail.

## Rules

- MUST evaluate the packaged effect-chain library as a curated set rather than as a neutral dump of available chains.
- SHOULD consider whether some underlying effects also need curation, not just the chain presets built from them.
- MUST keep this project separate from the effects and effect-chain UX project even where the two influence each other.
- MUST aim for a smaller, stronger, more understandable built-in library if cuts are warranted.

## Plan

Start by reviewing the current packaged effect chains for quality, redundancy, naming, organization, and usefulness in real Hypnograph workflows. Then decide what the library should feel like: broader but uneven, or smaller and more confident.

If useful, extend that review into the underlying effect set where weak or confusing chain entries are really symptoms of a deeper curation problem. The spike should end with a curation direction and a list of concrete follow-on changes such as rename, regroup, remove, refine, or add.
