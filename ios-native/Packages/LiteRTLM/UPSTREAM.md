# LiteRT-LM Swift wrapper provenance

The files under `Sources/LiteRTLM` are copied from the Swift wrapper in Google
LiteRT-LM tag `v0.13.0`, commit
`bbc5181df03c6962d7786ce4ad72c8565232d2b2`. Dimo carries two narrow additions
over that tag: exposure of the tag's existing native
`litert_lm_session_config_set_max_output_tokens` setter and its existing model
tokenizer count. They enforce the 192-token output cap and verify the rendered
prompt fits the 4,096-token runtime context.

The binary target URL and checksum are also copied from that tag's
`Package.swift`. The upstream v0.13.0 product declares `-all_load` through
SwiftPM `unsafeFlags`. Xcode rejects remote package products containing unsafe
flags when they are consumed by an application target. This local package
keeps the exact tagged wrapper and checksum-pinned binary while `project.yml`
applies `-all_load` to Dimo's own target.

When an upstream release provides a directly consumable package manifest,
replace this shim with an `exactVersion` remote package and remove Dimo's
temporary linker setting.
