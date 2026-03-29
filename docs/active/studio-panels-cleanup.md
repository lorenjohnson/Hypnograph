---
doc-status: in-progress
---

# Studio Panels Cleanup

## Overview

This project is a focused cleanup pass for the floating Studio panels and their remaining behavior issues after the recent windowing and panel work. The Hypnograms list has now been moved into the shared Studio panel system, so the scope is down to the one remaining play bar resize bug.

## Rules

- MUST keep this project focused on the remaining play bar resize bug only.
- MUST fix the remaining play bar resize drift within this project.
- MUST preserve the current panel model and avoid expanding this project into a new windowing-system rewrite.

## Plan

- Fix the remaining play bar resize drift so when layer-driven height changes happen it grows upward without panel position jitter.
- Move the old Hypnograms window into the regular Studio panel system without refactoring the window’s deeper model or purpose.

## Open Questions

- None beyond the exact implementation details of the two remaining tasks.
