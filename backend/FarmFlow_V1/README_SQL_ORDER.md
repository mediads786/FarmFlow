# FarmFlow V1 — Final Backend SQL Bundle

This folder is the clean fresh-install backend bundle derived from the **live Supabase database inventory**, not from historical SQL Editor tabs.

## Install order

Run on a NEW/EMPTY FarmFlow Supabase project in this exact order:

1. `00_BASE_SCHEMA.sql`
2. `01_CONSTRAINTS_INDEXES.sql`
3. `02_TAG_FORMAT.sql`
4. `03_PURCHASE_INTAKE.sql`
5. `04_INDUCTION.sql`
6. `05_SHIPMENTS_MORTALITY_REPORTING.sql`
7. `06_SETUP_MASTER_RESET.sql`
8. `07_RLS_GRANTS.sql`
9. `08_VERIFY_INSTALL.sql`

Do **not** run the fresh-install files over the existing working database.

## Intentional final fix

The live `master_reset_farm()` cleared shipment rows but did not restart the separate `shipment_code_seq`. The final bundle adds:

```sql
alter sequence public.shipment_code_seq restart with 1;
```

inside Master Reset so a true fresh reset restarts user-facing shipment numbering at `S001`.

Internal identity IDs are intentionally not reset; they are implementation keys and do not affect the FarmFlow user-facing numbering rules.

## Live-vs-final notes

- 8 public tables
- 33 live functions/RPCs
- 19 live RLS policies
- 18 live indexes
- 0 public views
- RLS enabled on all 8 public tables
- One animal-tag trigger for INSERT/UPDATE

## Items deliberately NOT silently changed

Two live functions remain side-by-side:
- `get_induction_report`
- `get_induction_report_v2`

The older function is retained in this bundle until the current Flutter code is checked for callers. Do not delete it merely because v2 exists.

The current `users` self-profile INSERT policy is also preserved because first-run Setup depends on the existing authentication/profile flow. Signup hardening should be handled as a separate release-security change, not mixed into schema reconstruction.

## Historical SQL

Old SQL files should now be classified only against this bundle/live map:
- CURRENT / REQUIRED
- SUPERSEDED
- ONE-TIME MIGRATION / REFERENCE ONLY
- DO NOT RUN

Historical patch order is not the install order.
