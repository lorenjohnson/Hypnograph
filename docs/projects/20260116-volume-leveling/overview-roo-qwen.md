# Volume Leveling (Player Settings): Overview

**Created**: 2026-01-20
**Status**: Draft

This document outlines the implementation of volume leveling for Hypnograph, ensuring consistent audio playback across hypnograms. The feature will apply a uniform gain adjustment to the audio mix, preventing volume spikes between clips while maintaining user control over volume levels.

Key decisions:
- **Audio Analysis**: RMS-based leveling (MVP), with future LUFS support.
- **Integration Point**: `AVMutableAudioMix` for preview/export parity.
- **Boundary Smoothing**: 150-300ms fade between clips.
- **User Control**: Toggle in Player Settings with RMS mode.

This implementation aligns with the Unified Player Architecture foundation and addresses user-reported volume inconsistency issues in clip history navigation.