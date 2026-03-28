---
doc-status: ready
---

# Location Overlay Effect

## Overview

Hypnograph often works with media whose meaning is tied to where it was captured. Today, location metadata (when present in Apple Photos assets) is not surfaced in the render output, and there's no simple "stamp the location" effect.

Add a new effect that reads an asset's geographic location (when available) and overlays a human-readable location label on top of the rendered layer.

## Plan

- MUST use existing effects/runtime hook architecture and avoid per-frame metadata lookups.
- MUST degrade gracefully when location is unavailable.

Phase 1 ships with a deterministic, non-ambiguous coordinate display (lat/long short form). Later phases might try adding reverse-geocoded place names and typography controls to see if it reliable and if it causes any lags. There is some desirability in terms of the personality of the product that lat/lng is as far as we go, as it is rather interesting to reflect on the map position in these numerical terms.

Overlay a short-form coordinate label, e.g.: `32° 18' N 122° 36' W` ("Degrees + Minutes" with hemisphere letters, Seconds are omitted for readability).

Typography options (font size, and family/face) are a nice-to-have.
