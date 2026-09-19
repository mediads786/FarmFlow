-- FarmFlow V1 — RLS and application-facing table grants
-- Policies below mirror the live policy inventory.
-- Grants are cleaned to least privilege where the live export contained noisy anon/TRUNCATE/TRIGGER grants.

alter table public.users enable row level security;
revoke all on table public.users from anon, authenticated;
alter table public.batches enable row level security;
revoke all on table public.batches from anon, authenticated;
alter table public.shipments enable row level security;
revoke all on table public.shipments from anon, authenticated;
alter table public.animals enable row level security;
revoke all on table public.animals from anon, authenticated;
alter table public.farm_lookup_values enable row level security;
revoke all on table public.farm_lookup_values from anon, authenticated;
alter table public.farm_tag_config enable row level security;
revoke all on table public.farm_tag_config from anon, authenticated;
alter table public.induction_corrections enable row level security;
revoke all on table public.induction_corrections from anon, authenticated;
alter table public.purchase_corrections enable row level security;
revoke all on table public.purchase_corrections from anon, authenticated;
grant select, insert, update on table public.users to authenticated;
grant select, insert, update, delete on table public.batches to authenticated;
grant select, insert, update, delete on table public.shipments to authenticated;
grant select, insert, update, delete on table public.animals to authenticated;
grant select, insert, update, delete on table public.farm_lookup_values to authenticated;
grant select on table public.induction_corrections to authenticated;
grant select on table public.purchase_corrections to authenticated;

-- Recreate live policies.

drop policy if exists "animals_active_users_select" on public.animals;
create policy "animals_active_users_select" on public.animals as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text, 'induction'::text]))))));

drop policy if exists "animals_induction_update" on public.animals;
create policy "animals_induction_update" on public.animals as permissive for update to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'induction'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'induction'::text]))))));

drop policy if exists "animals_management_delete" on public.animals;
create policy "animals_management_delete" on public.animals as permissive for delete to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = 'management'::text)))));

drop policy if exists "animals_purchase_insert" on public.animals;
create policy "animals_purchase_insert" on public.animals as permissive for insert to authenticated
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))));

drop policy if exists "batches_active_users_select" on public.batches;
create policy "batches_active_users_select" on public.batches as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text, 'induction'::text]))))));

drop policy if exists "batches_purchase_write" on public.batches;
create policy "batches_purchase_write" on public.batches as permissive for all to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))));

drop policy if exists "farm_lookup_values_delete_purchase_management" on public.farm_lookup_values;
create policy "farm_lookup_values_delete_purchase_management" on public.farm_lookup_values as permissive for delete to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))));

drop policy if exists "farm_lookup_values_insert_purchase_management" on public.farm_lookup_values;
create policy "farm_lookup_values_insert_purchase_management" on public.farm_lookup_values as permissive for insert to authenticated
with check (((created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text])))))));

drop policy if exists "farm_lookup_values_select_purchase_management" on public.farm_lookup_values;
create policy "farm_lookup_values_select_purchase_management" on public.farm_lookup_values as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))));

drop policy if exists "farm_lookup_values_update_purchase_management" on public.farm_lookup_values;
create policy "farm_lookup_values_update_purchase_management" on public.farm_lookup_values as permissive for update to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text]))))));

drop policy if exists "induction_corrections_management_select" on public.induction_corrections;
create policy "induction_corrections_management_select" on public.induction_corrections as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (u.role = 'management'::text)))));

drop policy if exists "purchase_corrections_management_select" on public.purchase_corrections;
create policy "purchase_corrections_management_select" on public.purchase_corrections as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = 'management'::text)))));

drop policy if exists "shipments_active_users_select" on public.shipments;
create policy "shipments_active_users_select" on public.shipments as permissive for select to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'purchase'::text, 'induction'::text]))))));

drop policy if exists "shipments_induction_insert" on public.shipments;
create policy "shipments_induction_insert" on public.shipments as permissive for insert to authenticated
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'induction'::text]))))));

drop policy if exists "shipments_induction_update" on public.shipments;
create policy "shipments_induction_update" on public.shipments as permissive for update to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'induction'::text]))))))
with check ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = ANY (ARRAY['management'::text, 'induction'::text]))))));

drop policy if exists "shipments_management_delete" on public.shipments;
create policy "shipments_management_delete" on public.shipments as permissive for delete to authenticated
using ((EXISTS ( SELECT 1
   FROM users u
  WHERE ((u.id = auth.uid()) AND (u.active IS TRUE) AND (lower(btrim(u.role)) = 'management'::text)))));

drop policy if exists "users can insert own profile" on public.users;
create policy "users can insert own profile" on public.users as permissive for insert to authenticated
with check ((auth.uid() = id));

drop policy if exists "users can read own profile" on public.users;
create policy "users can read own profile" on public.users as permissive for select to authenticated
using ((auth.uid() = id));

drop policy if exists "users can update own profile" on public.users;
create policy "users can update own profile" on public.users as permissive for update to authenticated
using ((auth.uid() = id))
with check ((auth.uid() = id));

-- Required sequence usage for shipment_code default.
grant usage, select on sequence public.shipment_code_seq to authenticated;
