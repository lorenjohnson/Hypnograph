---
doc-status: ready
---

# Sequences

## Overview

This project is now active because there is a workable first direction for sequence authorship instead of just open speculation. The current plan is to keep Hypnograph's history model for now, but layer a clearer authoring surface on top of it rather than jumping immediately to a full separate timeline model or a full model rename.

The main UI direction is a history timeline strip that can be shown or hidden above the play bar, using the same visual language as the current hypnogram and layer timelines. It should represent whole hypnograms across history as thumbnail segments, let the user move through history more legibly, and support in and out handles that snap to whole-hypnogram boundaries. That same surface appears to be the most promising first answer both for sequence selection and for a lot of the current history-UX ambiguity.

This also means timeline visibility probably needs to be considered together across levels. If the new history timeline can be shown and hidden above the play bar, the existing hypnogram timeline should likely gain the same kind of show or hide treatment at the same time rather than evolving as a separate UX pattern.

This also clarifies a few important semantics. Creating a new hypnogram while browsing older history already appears to append a new item at the live end and move playback there, so that is not the main bug. The more important problems are that playing from an older history item currently tends to continue into the next older-history item rather than into a newly generated hypnogram, and that creating a new hypnogram from older history appears to inherit prior-effect or carry-forward context from the latest clip at the end of history rather than from the clip the operator was actually viewing when they pressed `New`.

The preferred direction from here is to treat the currently viewed hypnogram as the semantic reference point for new generation when the operator is parked in history. There is also a stronger authoring idea worth testing: when the operator is in the middle of history and creates a new hypnogram, insert it at that point by default rather than always appending it at the end. That may be the best composition behavior, but it needs a brief technical and model-risk check before it becomes the default commitment.

This project intentionally leaves the deeper naming question open for now. The underlying model might eventually want to be renamed from `History` toward something more sequence-like, but v1 should not block on that. The immediate goal is a usable authoring surface and clearer semantics on top of the current history-based system.

FCPXML technical research and export notes live in [reference-fcpxml-export.md](./reference-fcpxml-export.md).

## Rules

- MUST keep the current history-based model usable while adding sequence authorship on top of it.
- MUST prototype a history timeline strip that uses the same general styling language as the existing hypnogram or layer timelines.
- SHOULD treat show or hide behavior for the history timeline and the existing hypnogram timeline as one coordinated UX decision.
- MUST let history range selection snap to whole-hypnogram boundaries rather than arbitrary sub-clip positions.
- MUST clarify what `Play` does when the operator is parked on an older history item and loop mode is off.
- MUST clarify what semantic reference point is used when creating a new hypnogram from older history.
- SHOULD test insertion at the current history position as the preferred authoring behavior for `New` if the model cost is acceptable.
- MUST NOT let longer-term naming or model-cleanup questions block the first usable version.

## Plan

Use [plan.md](./plan.md) for the concrete scenarios, prototype direction, and next implementation slices. The immediate work here is to validate the current baseline behavior, prototype the history timeline strip, and decide whether mid-history `New` should insert or append with improved carry-forward semantics.
