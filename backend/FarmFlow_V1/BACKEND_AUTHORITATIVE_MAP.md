# FarmFlow — Authoritative Live Backend Map

**Baseline:** live Supabase exports supplied during finalization on 2026-09-17.  
**Purpose:** this is the source-of-truth map for backend consolidation. Historical SQL snippets are not authoritative unless they reproduce this live state.

## 1. Live object inventory

- **Public tables:** 8
- **Live public functions/RPCs:** 33
- **RLS policies:** 19
- **Indexes:** 18
- **Views:** 0 (confirmed separately)
- **Public tables with RLS enabled:** 8 / 8
- **Trigger:** `animals_enforce_configured_farm_tag` — BEFORE INSERT/UPDATE on `animals` → `enforce_configured_farm_tag()`

### Tables

| Table | Columns | RLS Policies | Indexes | RLS |
|---|---:|---:|---:|---|
| `animals` | 12 | 4 | 4 | yes |
| `batches` | 13 | 2 | 2 | yes |
| `farm_lookup_values` | 7 | 4 | 3 | yes |
| `farm_tag_config` | 8 | 0 | 1 | yes |
| `induction_corrections` | 9 | 1 | 1 | yes |
| `purchase_corrections` | 10 | 1 | 4 | yes |
| `shipments` | 9 | 4 | 2 | yes |
| `users` | 8 | 3 | 1 | yes |

## 2. Live functions / RPCs

### Tag format / normalization
- `build_farm_tag(p_number bigint)`
- `farm_tag_number(p_input text)`
- `is_valid_configured_farm_tag(p_input text)`
- `normalize_farm_tag(p_input text)`
- `resolve_animal_tag(p_input text)`
- `max_used_farm_tag_number(nan)`
- `set_farm_tag_config(p_tag_mode text, p_tag_prefix text, p_tag_separator text)`
- `get_farm_tag_config(nan)`
- `enforce_configured_farm_tag(nan)`

### Purchase / intake
- `check_existing_animal_tags(p_tags text[])`
- `create_purchase_batch(p_purchase_date date, p_market_city text, p_supplier text, p_breed text, p_purchase_rate numeric, p_animal_count integer, p_total_weight numeric, p_already_tagged boolean, p_notes text, p_animals jsonb)`
- `get_purchase_correction_entry(p_tag text)`
- `correct_purchase_entry(p_tag text, p_new_tag text, p_new_purchase_weight numeric, p_market_city text, p_supplier text, p_breed text, p_purchase_rate numeric, p_notes text, p_reason text)`
- `delete_purchase_entry(p_tag text, p_reason text)`
- `purchase_batch_has_downstream_activity(p_batch_id bigint)`
- `max_used_batch_number(nan)`

### Induction
- `save_induction(p_entries jsonb)`
- `correct_induction(p_tag text, p_new_weight numeric, p_reason text)`
- `get_pending_induction(p_batch_code text)`
- `get_induction_report(p_batch_code text, p_purchase_date date)`
- `get_induction_report_v2(p_mode text, p_batch_code text, p_from_batch text, p_to_batch text, p_from_date date, p_to_date date)`

### Shipment / P&L
- `create_shipment(p_shipment_date date, p_animal_count integer, p_meat_rate numeric, p_offal_rate numeric, p_entries jsonb)`
- `search_shipments(p_search_mode text, p_from_shipment text, p_to_shipment text, p_from_date date, p_to_date date)`
- `set_shipment_feed_cost(p_shipment_code text, p_daily_feed_cost numeric)`
- `get_shipment_pl(p_shipment_code text)`
- `get_shipment_pl_summary(p_shipment_code text)`

### Dashboard / inventory / mortality
- `get_live_inventory(nan)`
- `get_dashboard_summary(nan)`
- `get_recent_activity_line(p_position integer)`
- `record_mortality(p_tag text, p_mortality_date date)`

### Setup / reset
- `farmflow_setup_complete(nan)`
- `master_reset_farm(nan)`
- `complete_farm_reconfiguration(p_farm_name text, p_farm_code text, p_manager_name text)`


## 3. Constraints / foreign keys / checks

### animals
- **FK** `animals_batch_id_fkey` — FOREIGN KEY (batch_id) REFERENCES batches(id) ON DELETE RESTRICT
- **CHECK** `animals_induction_weight_min_check` — CHECK (((induction_weight IS NULL) OR (induction_weight >= (1)::numeric))) NOT VALID
- **PK** `animals_pkey` — PRIMARY KEY (id)
- **FK** `animals_shipment_id_fkey` — FOREIGN KEY (shipment_id) REFERENCES shipments(id) ON DELETE RESTRICT
- **UNIQUE** `animals_tag_key` — UNIQUE (tag)

### batches
- **UNIQUE** `batches_batch_code_key` — UNIQUE (batch_code)
- **FK** `batches_created_by_fkey` — FOREIGN KEY (created_by) REFERENCES auth.users(id)
- **PK** `batches_pkey` — PRIMARY KEY (id)

### farm_lookup_values
- **CHECK** `farm_lookup_values_category_check` — CHECK ((category = ANY (ARRAY['market'::text, 'supplier'::text, 'breed'::text])))
- **FK** `farm_lookup_values_created_by_fkey` — FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT
- **PK** `farm_lookup_values_pkey` — PRIMARY KEY (id)
- **CHECK** `farm_lookup_values_value_check` — CHECK (((char_length(btrim(value)) >= 1) AND (char_length(btrim(value)) <= 100)))

### farm_tag_config
- **FK** `farm_tag_config_configured_by_fkey` — FOREIGN KEY (configured_by) REFERENCES users(id) ON DELETE RESTRICT
- **CHECK** `farm_tag_config_id_check` — CHECK ((id = 1))
- **PK** `farm_tag_config_pkey` — PRIMARY KEY (id)
- **CHECK** `farm_tag_config_shape_check` — CHECK ((((tag_mode = 'numeric'::text) AND (tag_prefix IS NULL) AND (tag_separator IS NULL)) OR ((tag_mode = 'prefixed'::text) AND (tag_prefix IS NOT NULL) AND (tag_separator IS NOT NULL))))
- **CHECK** `farm_tag_config_tag_min_digits_check` — CHECK (((tag_min_digits >= 1) AND (tag_min_digits <= 18)))
- **CHECK** `farm_tag_config_tag_mode_check` — CHECK ((tag_mode = ANY (ARRAY['prefixed'::text, 'numeric'::text])))

### induction_corrections
- **FK** `induction_corrections_animal_id_fkey` — FOREIGN KEY (animal_id) REFERENCES animals(id) ON DELETE RESTRICT
- **FK** `induction_corrections_changed_by_fkey` — FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE RESTRICT
- **CHECK** `induction_corrections_new_weight_check` — CHECK ((new_weight >= (1)::numeric))
- **PK** `induction_corrections_pkey` — PRIMARY KEY (id)
- **CHECK** `induction_corrections_reason_check` — CHECK ((char_length(btrim(reason)) >= 3))

### purchase_corrections
- **CHECK** `purchase_corrections_action_check` — CHECK ((action = ANY (ARRAY['edit'::text, 'delete'::text])))
- **FK** `purchase_corrections_changed_by_fkey` — FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE RESTRICT
- **PK** `purchase_corrections_pkey` — PRIMARY KEY (id)
- **CHECK** `purchase_corrections_reason_check` — CHECK ((char_length(btrim(reason)) >= 3))

### shipments
- **FK** `shipments_created_by_fkey` — FOREIGN KEY (created_by) REFERENCES auth.users(id)
- **PK** `shipments_pkey` — PRIMARY KEY (id)
- **UNIQUE** `shipments_shipment_code_key` — UNIQUE (shipment_code)

### users
- **FK** `users_id_fkey` — FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
- **PK** `users_pkey` — PRIMARY KEY (id)
- **CHECK** `users_role_check` — CHECK ((role = ANY (ARRAY['management'::text, 'purchase'::text, 'induction'::text])))


## 4. RLS policy inventory

### animals
- `animals_active_users_select` — SELECT — roles `{authenticated}`
- `animals_induction_update` — UPDATE — roles `{authenticated}`
- `animals_management_delete` — DELETE — roles `{authenticated}`
- `animals_purchase_insert` — INSERT — roles `{authenticated}`

### batches
- `batches_active_users_select` — SELECT — roles `{authenticated}`
- `batches_purchase_write` — ALL — roles `{authenticated}`

### farm_lookup_values
- `farm_lookup_values_delete_purchase_management` — DELETE — roles `{authenticated}`
- `farm_lookup_values_insert_purchase_management` — INSERT — roles `{authenticated}`
- `farm_lookup_values_select_purchase_management` — SELECT — roles `{authenticated}`
- `farm_lookup_values_update_purchase_management` — UPDATE — roles `{authenticated}`

### induction_corrections
- `induction_corrections_management_select` — SELECT — roles `{authenticated}`

### purchase_corrections
- `purchase_corrections_management_select` — SELECT — roles `{authenticated}`

### shipments
- `shipments_active_users_select` — SELECT — roles `{authenticated}`
- `shipments_induction_insert` — INSERT — roles `{authenticated}`
- `shipments_induction_update` — UPDATE — roles `{authenticated}`
- `shipments_management_delete` — DELETE — roles `{authenticated}`

### users
- `users can insert own profile` — INSERT — roles `{authenticated}`
- `users can read own profile` — SELECT — roles `{authenticated}`
- `users can update own profile` — UPDATE — roles `{authenticated}`


## 5. Effective table-grant baseline

Only application-facing roles are summarized here; `postgres` owner grants are omitted.

### animals
- `authenticated`: DELETE, INSERT, SELECT, UPDATE
- `service_role`: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

### batches
- `authenticated`: DELETE, INSERT, SELECT, UPDATE
- `service_role`: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

### farm_lookup_values
- `authenticated`: DELETE, INSERT, SELECT, UPDATE
- `service_role`: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

### farm_tag_config
- `service_role`: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

### induction_corrections
- `anon`: REFERENCES, SELECT, TRIGGER, TRUNCATE
- `authenticated`: REFERENCES, SELECT, TRIGGER, TRUNCATE
- `service_role`: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE

### purchase_corrections
- `authenticated`: SELECT
- `service_role`: DELETE, INSERT


## 6. Current authoritative decisions

- The **live database state beats old SQL Editor tabs and old patch files**.
- Old SQL will be classified against this map as:
  - `CURRENT / REQUIRED`
  - `SUPERSEDED`
  - `ONE-TIME MIGRATION / REFERENCE`
  - `DO NOT RUN`
- `farm_tag_config` is intentionally not directly granted to `authenticated`; application access is through RPCs.
- Tag normalization/validation is backend-authoritative.
- `farmflow_setup_complete()` currently requires both an active Management profile and row `farm_tag_config.id = 1`.
- `master_reset_farm()` currently preserves `auth.users` / `public.users` and deletes operational/configuration data.
- Master Reset delete order is compatible with the live restrictive foreign keys: correction rows → animals → shipments/batches → lookup values → tag config.

## 7. Review flags found during consolidation

| Object | Status | Finding |
|---|---|---|
| `get_induction_report` | **REVIEW / likely legacy** | Both get_induction_report and get_induction_report_v2 are live. Current UI work has been using v2; verify no widget still calls v1 before retiring it. |
| `get_pending_induction` | **REVIEW** | Uses exact batch_code equality. If any current widget calls it directly, shorthand B01 will not match stored B001 unless the caller normalizes first. |
| `create_shipment` | **REVIEW** | Live function allows offal_rate = 0 because it rejects only values < 0. Final UI/backend rule should be reconciled if offal must be strictly greater than zero. |
| `induction_corrections grants` | **CLEANUP** | Live grants include anon/authenticated REFERENCES/SELECT/TRIGGER/TRUNCATE. RLS still blocks anonymous row access because there is no anon policy, but the grants are broader/noisier than needed. |
| `sequence metadata` | **MISSING EXPORT** | shipment_code uses shipment_code_seq, but sequence definitions/state were not included in the exports. Identity/sequence metadata is required for a true fresh-install SQL bundle. |
| `Master Reset numbering` | **VERIFY** | Master Reset deletes shipment rows but the live shipment_code column is sequence-backed. Unless the reset RPC also restarts shipment_code_seq, shipment numbering will continue after reset instead of returning to S001. |

## 8. Fresh-install bundle plan

The final backend package should be generated in dependency order, not historical chronology:

1. **00_BASE_SCHEMA.sql** — sequences/identity metadata, tables, defaults, PK/UNIQUE/CHECK constraints.
2. **01_FOREIGN_KEYS_INDEXES.sql** — FKs and non-constraint indexes.
3. **02_TAG_FORMAT.sql** — tag config table support, tag helpers, normalizer, validator, trigger.
4. **03_PURCHASE_INTAKE.sql** — intake creation, duplicate/sequence checks, purchase correction/audit helpers.
5. **04_INDUCTION.sql** — induction save/correction/report functions.
6. **05_SHIPMENTS_MORTALITY_REPORTING.sql** — shipments, mortality, P&L, inventory/dashboard/report functions.
7. **06_SETUP_MASTER_RESET.sql** — setup status, reconfiguration, master reset.
8. **07_RLS_GRANTS.sql** — RLS enablement, policies, least-privilege grants.
9. **README_SQL_ORDER.md** — exact install order, verification queries, and old-file classification.


## 9. Sequence / identity metadata — COMPLETE

The final sequence/identity export confirms:

| Table / column | Mechanism | Sequence |
|---|---|---|
| `animals.id` | IDENTITY BY DEFAULT | `public.animals_id_seq` |
| `batches.id` | IDENTITY BY DEFAULT | `public.batches_id_seq` |
| `induction_corrections.id` | IDENTITY ALWAYS | `public.induction_corrections_id_seq` |
| `purchase_corrections.id` | IDENTITY ALWAYS | `public.purchase_corrections_id_seq` |
| `shipments.id` | IDENTITY BY DEFAULT | `public.shipments_id_seq` |
| `shipments.shipment_code` | explicit `nextval()` default | `shipment_code_seq` |

`shipments.shipment_code` is not an identity column, so `pg_get_serial_sequence()` returns null for it; however its live default explicitly calls `nextval('shipment_code_seq'::regclass)`. The fresh-install bundle therefore must create `shipment_code_seq` before creating/altering that default.

### Master Reset numbering decision

The current `master_reset_farm()` deletes shipment rows but does **not** restart `shipment_code_seq`. Therefore a reset currently clears shipment data while the next shipment code continues from the previous sequence value.

For a true “start completely clean” reset, the final reset function should explicitly restart `shipment_code_seq` to 1. Identity row IDs do not need to be user-visible/reset unless deliberately required.

The live-backend inventory is now complete enough to build the authoritative fresh-install SQL bundle without guessing.


## 10. Historical SQL classification rule

When an old SQL file is supplied, compare its resulting objects to this live map:
- If it creates an object that exists live and matches the current definition → **CURRENT/REQUIRED**.
- If it defines an older version of a live object → **SUPERSEDED / DO NOT RUN**.
- If it performs a one-time `ALTER`, migration, data cleanup, or patch already reflected in the live schema → **REFERENCE ONLY**.
- If it conflicts with current schema/RLS/function definitions → **DO NOT RUN**.
