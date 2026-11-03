# Services

The Xcode project's Services group points here. Future in-process Swift services own document persistence, AI orchestration and provider adapters. No hosted backend is required.

Ticket 002 adds the group; it is part of the single app module. `Persistence/DocumentStore.swift` implements document package save/load (ticket 005, `docs/database/document-schema-v1.md`). Dependencies, security boundaries and contracts remain governed by `docs/tdd/tdd.md` and later tickets.

`Providers/` implements the generic OpenAI-compatible streaming adapter, Qwen region/model preset data, bounded SSE parser, cancellable ephemeral URLSession transport and endpoint-scoped this-device-only Keychain store (007). `AI/ModelContent.swift` validates PNGs and builds Base64 data URLs. No provider/response/key logging, automatic retries or failover are added. [Contract and evidence](../docs/api/providers.md); live Qwen acceptance remains pending.

Library metadata (009): rename now atomically rewrites a cloned package's manifest while preserving every other file byte. Listing rejects mismatched manifest/folder IDs, with stable equal-date ordering. The app library acquires the same in-process editing claim before rename/delete; permanent deletion still requires an explicit library confirmation and has no trash until PE-004.
