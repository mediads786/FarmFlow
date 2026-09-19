-- FarmFlow V1 — setup and Master Reset

CREATE OR REPLACE FUNCTION public.farmflow_setup_complete()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    exists (
      select 1
      from public.users u
      where u.active is true
        and lower(btrim(u.role)) = 'management'
    )
    and exists (
      select 1
      from public.farm_tag_config c
      where c.id = 1
    );
$function$;

CREATE OR REPLACE FUNCTION public.complete_farm_reconfiguration(p_farm_name text, p_farm_code text, p_manager_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_farm_name text := btrim(coalesce(p_farm_name, ''));
  v_farm_code text := btrim(coalesce(p_farm_code, ''));
  v_manager_name text := btrim(coalesce(p_manager_name, ''));
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(u.role))
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if v_role is distinct from 'management' then
    raise exception 'Management access required';
  end if;

  if char_length(v_farm_name) < 2 then
    raise exception 'Farm Name is required';
  end if;

  if char_length(v_farm_code) < 2 then
    raise exception 'Farm Code is required';
  end if;

  if char_length(v_manager_name) < 2 then
    raise exception 'Manager Name is required';
  end if;

  -- One-farm V1: the farm identity is shared by all preserved profiles.
  update public.users
  set farm_name = v_farm_name,
      farm_code = v_farm_code
  where id is not null;

  update public.users
  set name = v_manager_name,
      active = true
  where id = v_user_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.master_reset_farm()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(u.role))
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if v_role is distinct from 'management' then
    raise exception 'Management access required';
  end if;

  -- Prevent two reset attempts from running at the same time.
  perform pg_advisory_xact_lock(hashtext('farmflow_master_reset'));

  -- Child/audit rows first. induction_corrections has a restrictive FK to animals.
  delete from public.induction_corrections where id is not null;
  delete from public.purchase_corrections where id is not null;

  -- Animals reference batches and shipments, so remove animals first.
  -- Mortality is stored on the animal record, so it is cleared with animals.
  delete from public.animals where id is not null;
  delete from public.shipments where id is not null;
  delete from public.batches where id is not null;

  -- User-created master lookup values restart from empty.
  delete from public.farm_lookup_values where id is not null;

  -- Deleting the tag configuration unlocks Tag Format for the fresh Setup run.
  delete from public.farm_tag_config where id is not null;

  -- Fresh reset must restart user-facing shipment numbering.
  alter sequence public.shipment_code_seq restart with 1;

  return 'Farm reset completed successfully.';
end;
$function$;
