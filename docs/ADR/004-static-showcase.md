# ADR 004 — Separate static, view-only public showcase

**Status:** Accepted for the public repository; recorded retrospectively (September 2026).

## Context
The original mutable demonstration was not suitable for public release: testing exposed an invalid generated animal tag (`00NULL`) and a failing shipment operation. Repairing a parallel implementation of production transactions was disproportionate to the portfolio objective. Publishing production credentials or a writable shared dataset was not acceptable.

## Decision
Create `FarmFlow-Showcase` as a separate working folder. Retain the established demo screens, USD formatting, fictional markets and sample records; disable transaction controls **and** backing data-store writes. Publish only the compiled Flutter Web site. Do not connect it to production Supabase.

## Alternatives considered
A separate Supabase demonstration database could exercise real transactional behavior but would need independent account/data isolation, reset, operational monitoring and integrity testing. A mutable in-memory demo was attempted and rejected after defects. A view-only showcase meets the narrower goal of demonstrating the product interface and operational reports.

## Consequences
Visitors can browse but cannot demonstrate a complete live purchase-to-shipment transaction. Role selection is for presenting screens, not real authentication. Shipment-page search remains a known limitation; the app does not claim full production functional parity. Full V1 backend SQL may be documented in this repository, but it is not executed by the showcase.

## Evidence and limitations
The showcase Flutter tests passed, the release web build succeeded, and the restricted controls and navigation were checked locally. The live Vercel URL must still be deployed and verified separately. Screenshots are illustrative fictional records.
