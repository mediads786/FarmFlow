# ADR 002 — Supabase PostgreSQL for persistent operations

**Status:** Accepted for full FarmFlow V1; recorded retrospectively (September 2026).

## Context
Farm operations involve unique animal tags and batch identifiers, life-cycle transitions, purchases, inductions, shipments, mortality, corrections and financial reporting. Frontend-only validation cannot enforce persistent integrity across users or concurrent operations.

## Decision
Use Supabase Auth and PostgreSQL for the full application. Enforce lasting invariants with schema constraints, authorization with RLS and grants, and suitable transactional business operations with SQL functions/RPCs. Keep UI checks for immediate feedback without treating the browser as the authoritative trust boundary.

## Alternatives considered
A browser-only store is suitable for a demonstration but cannot serve as a trustworthy persistent farm record. A separate custom application server was not necessary for the V1 data model and RPC approach.

## Consequences
Changes to tag rules, schema, policies or RPC behavior require coordinated database review and migration. Permissions must be assessed at the database layer as well as in the interface. The [backend reference](../../backend/FarmFlow_V1/) represents full V1, not a live public demo service; it must not be run on an existing production database.

## Evidence and limitations
The backend inventory documents live object names, constraints, roles and RPCs captured during V1 consolidation. This public showcase release did not redeploy or integration-test the complete SQL bundle.
