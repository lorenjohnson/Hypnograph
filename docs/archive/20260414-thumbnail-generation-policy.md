# Thumbnail Generation Policy

This cleanup pass is largely complete. Thumbnail behavior is now split into three clearer responsibilities:

- explicit snapshots still come from the current rendered frame
- composition preview thumbnails are deterministic document/listing images rather than opportunistic live-frame captures
- timeline/media thumbnails share a lower-level generator while keeping consumer-specific stores

The main value of this project was clarifying policy and ownership, not building a universal thumbnail manager. That clarification is now in the codebase.

The only meaningful follow-on to keep in view is tuning rather than architecture:

- continue observing whether any thumbnail jobs should be delayed more aggressively during active playback
- tune cache size, priority, and delay policy from real usage rather than from further speculative abstraction

Supersedes:

- `docs/active/thumbnail-generation-policy.md`
