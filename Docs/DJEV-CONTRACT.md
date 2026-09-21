# Legacy DJev contract — compatibility note

This document is retained only for historical compatibility with pre-v0.8 integrations.

**Current production contract:** `Docs/MULTIMODAL-CRITIC-CONTRACT-v0.8.md`.

PhotoGuide v0.8 no longer treats DJev as a fixed evaluator that only emits old Goal observations. DJev is one possible implementation of the generic multimodal photography critic. The primary response is now a `SemanticCritique` containing Recipe-specific multi-dimensional photography assessments and professional advice over sampled frames.

Legacy `slots`, `observations`, `imageBase64`, `DJEV_ENDPOINT` and `DJEV_TOKEN` remain accepted to ease migration, but new integrations should use:

```text
MULTIMODAL_CRITIC_ENDPOINT
MULTIMODAL_CRITIC_TOKEN
```

and the v0.8 sampled-frame critic request/response contract.
