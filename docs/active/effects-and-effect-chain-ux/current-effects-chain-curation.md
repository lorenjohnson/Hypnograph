---
doc-status: working
source: /Users/lorenjohnson/dev/HypnoPackages/HypnoCore/Renderer/Effects/Library/effects-default.json
---

# Current Effects Chain Curation

This is the live working list for effect chains that feel worth keeping, refining, or dropping from the release library. The reference point is the current Effect Chains Library in the local install, not only the bundle defaults. The intention, though, is to build up the library into the set that should eventually become the bundled defaults.

The most useful input for this document is simple:

- which chains actually feel worth keeping
- what visual direction each one serves
- how they might want to be tuned or renamed later

## Working Notes

### NTSC Analog Chain v2

A strong vintage VHS / analog TV chain that is already working well. Very useful for creating a blurry retro composite feeling. Helps layered composites read more like one surface instead of separate floating layers, which is one of the important goals in the composite look. Softer than the other NTSC-style chain, and probably useful enough in that softer role that both may be worth keeping. Still wants comparison and tuning against the other NTSC-style chain, but no longer necessarily as a one-or-the-other decision.

### Overloaded 12

An extreme abstracting chain that pushes footage toward a painterly, experimental image while still preserving enough silhouetted motion to feel alive. The current green-orange tendency seems to be part of its identity.

### YUV Invert + NW LUT + Smear

A high-contrast experimental chain that pushes footage into an alternate, fluorescent-feeling color space with a strong synthetic smear. This may be worth trimming down slightly, but the overall result is already useful.

### Pastel Invert Grainy

A grainy, half-tone-feeling, time-difference smear chain with a pastel-inverted palette and a strong experimental character. It seems especially strong at lower play rates.

### Ghostly Hue Wobble

A ghosted, black-and-white, old-timey smear chain with a smoother drifting motion character. It likely wants hue wobble severity and frequency reduced.

### Dark BW Ghost

A dark, silhouetted black-and-white ghosting chain with heavy presence in the blacks and a strong haunted smear. It likely overlaps heavily with `Ghostly Hue Wobble`, and may eventually become a choice between the two or a merged best-of variant. It probably wants similar tuning: reduce hue wobble frequency and severity, and maybe reduce the ghosting a little while keeping the deep black silhouette quality.

### Moshy Impressions

A milder halftone / printed-image chain with frame-difference accumulation and a more restrained color palette.

### Classic Chrome Light

A gentler palette-shift chain that nudges ordinary footage toward a more photographic, film-adjacent color world.

### Overloaded 11

A darker alternate-color-space overload chain with a simpler core built largely from basic treatment plus frame-difference behavior. It tends toward dark greens, especially on faces, and may want retuning or eventual consolidation with `Overloaded 12`.

### Pastel Dream Machine

Pretty well named already, though it may want slightly less brightness or saturation so it fits the word `Pastel` better. Useful for a rainbowy, bright, almost Adventure Time sort of visual reality. Built largely from a basic treatment, a random LUT, and temporal smear.

### Black and Purple

A black-and-white-adjacent chain with a duotone feeling, especially purple in the midtones. Built from a more layered combination including two basic passes, Color Echo Metal, and I-Frame Compress. Time-based, but not overwhelmingly so. Very artsy, generally high contrast, with blown-out highlights and darker shadows that stay close to black with a little green-black in them.

## Most Likely to be Eliminated

- `Metal Chained`
- `Ghost + Hold`
- `Frame Diff + Text + Sat`
- `Glitch and Time`
- `Dec 28: Set 1`
- `YUV Invert + Text`
- `Text + Ghost`
- `RGB + Text`
- `LUT Effect`
- `VLOG LUT`
- `OpFlow Test`
- `Effect`
- `Effect 2`
- `NTSC Analog Chain (Retro Inspired)`
