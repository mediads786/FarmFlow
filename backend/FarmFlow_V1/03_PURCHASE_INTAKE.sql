-- FarmFlow V1 — purchase/intake and purchase corrections

CREATE OR REPLACE FUNCTION public.max_used_batch_number()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select greatest(
    coalesce((
      select max(
        substring(
          upper(trim(b.batch_code))
          from '^B([0-9]+)$'
        )::bigint
      )
      from public.batches b
      where trim(b.batch_code) ~* '^B[0-9]+$'
    ), 0),
    coalesce((
      select max(
        substring(
          upper(trim(pc.batch_code))
          from '^B([0-9]+)$'
        )::bigint
      )
      from public.purchase_corrections pc
      where trim(pc.batch_code) ~* '^B[0-9]+$'
    ), 0)
  );
$function$;

CREATE OR REPLACE FUNCTION public.purchase_batch_has_downstream_activity(p_batch_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.animals a
    where a.batch_id = p_batch_id
      and (
        lower(btrim(a.status)) <> 'purchased'
        or a.induction_weight is not null
        or a.induction_date is not null
        or a.shipment_id is not null
        or a.out_weight is not null
        or a.meat_weight is not null
        or a.mortality_date is not null
        or exists (
          select 1
          from public.induction_corrections ic
          where ic.animal_id = a.id
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.check_existing_animal_tags(p_tags text[])
 RETURNS TABLE(input_tag text, existing_tag text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_last_tag_number bigint := 0;
  v_count integer := 0;
  v_distinct integer := 0;
  v_min bigint;
  v_max bigint;
  v_bad_tag text;
begin
  v_count := coalesce(cardinality(p_tags), 0);

  if v_count = 0 then
    return;
  end if;

  ------------------------------------------------------------------
  -- 1) REQUIRED TAG CHECK
  -- Use EXISTS so NULL/blank values cannot slip through because of
  -- SELECT ... INTO assigning NULL to v_bad_tag.
  ------------------------------------------------------------------
  if exists (
    select 1
    from unnest(p_tags) as t
    where nullif(btrim(coalesce(t, '')), '') is null
  ) then
    raise exception 'Tag Number is required for every tagged animal';
  end if;

  ------------------------------------------------------------------
  -- 2) CONFIGURED FARM TAG FORMAT
  -- Shorthand/case variants are accepted by the shared validator,
  -- e.g. FF-1 / ff-01, and later normalized to canonical storage.
  ------------------------------------------------------------------
  select btrim(t)
    into v_bad_tag
  from unnest(p_tags) as t
  where not public.is_valid_configured_farm_tag(btrim(t))
  limit 1;

  if v_bad_tag is not null then
    raise exception
      'Invalid Tag Number %. Use the configured farm tag format, for example %',
      v_bad_tag,
      public.build_farm_tag(1);
  end if;

  ------------------------------------------------------------------
  -- 3) LOGICAL DUPLICATES INSIDE THIS ENTRY
  ------------------------------------------------------------------
  select count(distinct public.normalize_farm_tag(btrim(t)))
    into v_distinct
  from unnest(p_tags) as t;

  if v_distinct <> v_count then
    raise exception 'Duplicate tags found in purchase entry';
  end if;

  ------------------------------------------------------------------
  -- 4) EXISTING DATABASE DUPLICATES
  -- Preserve the existing RPC contract: duplicate rows are returned,
  -- not raised, because the Flutter code expects existing_tag rows.
  ------------------------------------------------------------------
  if exists (
    select 1
    from unnest(p_tags) as t
    join public.animals a
      on public.normalize_farm_tag(a.tag)
       = public.normalize_farm_tag(btrim(t))
  ) then
    return query
    select distinct
      btrim(t) as input_tag,
      a.tag as existing_tag
    from unnest(p_tags) as t
    join public.animals a
      on public.normalize_farm_tag(a.tag)
       = public.normalize_farm_tag(btrim(t))
    order by 1, 2;

    return;
  end if;

  ------------------------------------------------------------------
  -- 5) EXACT NEXT NO-GAP SEQUENCE
  ------------------------------------------------------------------
  select public.max_used_farm_tag_number()
    into v_last_tag_number;

  select
    min(public.farm_tag_number(btrim(t))),
    max(public.farm_tag_number(btrim(t)))
  into v_min, v_max
  from unnest(p_tags) as t;

  if v_min <> v_last_tag_number + 1
     or v_max <> v_last_tag_number + v_count then
    raise exception
      'Tag sequence must continue from % with no gaps. For % animal(s), last tag must be %',
      public.build_farm_tag(v_last_tag_number + 1),
      v_count,
      public.build_farm_tag(v_last_tag_number + v_count);
  end if;

  -- No duplicates found: return zero rows, preserving the existing contract.
  return;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_purchase_batch(p_purchase_date date, p_market_city text, p_supplier text, p_breed text, p_purchase_rate numeric, p_animal_count integer, p_total_weight numeric, p_already_tagged boolean, p_notes text, p_animals jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  v_batch_id bigint;
  v_batch_code text;

  v_actual_count integer;
  v_actual_weight numeric;
  v_distinct_tags integer;

  v_item jsonb;
  v_tag text;
  v_weight numeric;
  v_existing_tag text;

  v_last_tag_number bigint := 0;
  v_next_tag_number bigint;
  v_min_input_tag_number bigint;
  v_max_input_tag_number bigint;
  v_distinct_input_numbers integer;

  v_last_batch bigint := 0;
  v_next_batch bigint;
begin
  -- BASIC VALIDATION
  if p_animal_count <= 0 then
    raise exception 'Animal count must be greater than zero';
  end if;

  if p_purchase_rate <= 0 then
    raise exception 'Purchase rate must be greater than zero';
  end if;

  if p_total_weight <= 0 then
    raise exception 'Total weight must be greater than zero';
  end if;

  if p_animals is null or jsonb_typeof(p_animals) <> 'array' then
    raise exception 'Animal data must be an array';
  end if;

  select
    count(*),
    coalesce(sum((x->>'weight')::numeric), 0)
  into v_actual_count, v_actual_weight
  from jsonb_array_elements(p_animals) x;

  if v_actual_count <> p_animal_count then
    raise exception
      'Animal count mismatch. Declared %, entered %',
      p_animal_count,
      v_actual_count;
  end if;

  if round(v_actual_weight, 2) <> round(p_total_weight, 2) then
    raise exception
      'Weight mismatch. Declared %, entered %',
      p_total_weight,
      v_actual_weight;
  end if;

  -- Serialize manual validation and automatic generation under the same lock.
  perform pg_advisory_xact_lock(hashtext('farmflow_ff_tag_generation'));

  select public.max_used_farm_tag_number()
    into v_last_tag_number;

  if p_already_tagged then
    -- 1) Required + valid configured format.
    if exists (
      select 1
      from jsonb_array_elements(p_animals) x
      where nullif(trim(x->>'tag'), '') is null
         or not public.is_valid_configured_farm_tag(trim(x->>'tag'))
    ) then
      raise exception
        'Invalid Tag Number. Use the configured farm tag format, for example %',
        public.build_farm_tag(v_last_tag_number + 1);
    end if;

    -- 2) Logical duplicate tags inside this purchase.
    select count(distinct public.normalize_farm_tag(trim(x->>'tag')))
      into v_distinct_tags
    from jsonb_array_elements(p_animals) x;

    if v_distinct_tags <> v_actual_count then
      raise exception 'Duplicate tags found in purchase entry';
    end if;

    -- 3) Existing DB duplicate check BEFORE sequence check and BEFORE batch insert.
    select a.tag
      into v_existing_tag
    from public.animals a
    join (
      select public.normalize_farm_tag(trim(x->>'tag')) as normalized_tag
      from jsonb_array_elements(p_animals) x
    ) incoming
      on public.normalize_farm_tag(a.tag) = incoming.normalized_tag
    limit 1;

    if v_existing_tag is not null then
      raise exception 'Tag % already exists', v_existing_tag;
    end if;

    -- 4) Exact next no-gap sequence.
    select
      min(public.farm_tag_number(trim(x->>'tag'))),
      max(public.farm_tag_number(trim(x->>'tag'))),
      count(distinct public.farm_tag_number(trim(x->>'tag')))
    into
      v_min_input_tag_number,
      v_max_input_tag_number,
      v_distinct_input_numbers
    from jsonb_array_elements(p_animals) x;

    if v_min_input_tag_number <> v_last_tag_number + 1
       or v_max_input_tag_number <> v_last_tag_number + v_actual_count
       or v_distinct_input_numbers <> v_actual_count then
      raise exception
        'Tag sequence must continue from % with no gaps. For % animal(s), last tag must be %',
        public.build_farm_tag(v_last_tag_number + 1),
        v_actual_count,
        public.build_farm_tag(v_last_tag_number + v_actual_count);
    end if;
  end if;

  -- BATCH NUMBER
  perform pg_advisory_xact_lock(hashtext('farmflow_batch_code_generation'));

  select public.max_used_batch_number()
    into v_last_batch;

  v_next_batch := v_last_batch + 1;
  v_batch_code :=
    'B' || lpad(
      v_next_batch::text,
      greatest(3, length(v_next_batch::text)),
      '0'
    );

  -- CREATE BATCH only after every validation has passed.
  insert into public.batches (
    batch_code,
    purchase_date,
    market_city,
    supplier,
    breed,
    purchase_rate,
    animal_count,
    total_weight,
    already_tagged,
    notes,
    created_by
  ) values (
    v_batch_code,
    p_purchase_date,
    p_market_city,
    p_supplier,
    p_breed,
    p_purchase_rate,
    p_animal_count,
    p_total_weight,
    p_already_tagged,
    p_notes,
    auth.uid()
  )
  returning id into v_batch_id;

  -- CREATE ANIMALS
  v_next_tag_number := v_last_tag_number;

  for v_item in
    select value from jsonb_array_elements(p_animals)
  loop
    v_weight := (v_item->>'weight')::numeric;

    if v_weight <= 0 then
      raise exception 'Animal weight must be greater than zero';
    end if;

    if p_already_tagged then
      -- ALWAYS store canonical configured form.
      v_tag := public.normalize_farm_tag(trim(v_item->>'tag'));
    else
      v_next_tag_number := v_next_tag_number + 1;
      v_tag := public.build_farm_tag(v_next_tag_number);
    end if;

    if exists (select 1 from public.animals where tag = v_tag) then
      raise exception 'Tag % already exists', v_tag;
    end if;

    insert into public.animals (
      tag,
      batch_id,
      purchase_weight,
      status
    ) values (
      v_tag,
      v_batch_id,
      v_weight,
      'purchased'
    );
  end loop;

  return v_batch_code;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_purchase_correction_entry(p_tag text)
 RETURNS TABLE(animal_id bigint, stored_tag text, purchase_weight numeric, batch_id bigint, batch_code text, purchase_date date, market_city text, supplier text, breed text, purchase_rate numeric, animal_count integer, total_weight numeric, already_tagged boolean, notes text, can_correct boolean, lock_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_stored_tag text;
  v_animal public.animals%rowtype;
  v_batch public.batches%rowtype;
  v_locked boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(u.role))
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if coalesce(v_role, '') not in ('management', 'purchase') then
    raise exception 'Purchase or Management access required';
  end if;

  if nullif(btrim(p_tag), '') is null then
    raise exception 'Tag is required';
  end if;

  v_stored_tag := public.resolve_animal_tag(btrim(p_tag));

  if v_stored_tag is null then
    raise exception 'Tag not found';
  end if;

  select a.*
    into v_animal
  from public.animals a
  where a.tag = v_stored_tag;

  if not found then
    raise exception 'Tag not found';
  end if;

  select b.*
    into v_batch
  from public.batches b
  where b.id = v_animal.batch_id;

  if not found then
    raise exception 'Purchase batch not found';
  end if;

  v_locked := public.purchase_batch_has_downstream_activity(v_batch.id);

  return query
  select
    v_animal.id,
    v_animal.tag,
    v_animal.purchase_weight,
    v_batch.id,
    v_batch.batch_code,
    v_batch.purchase_date,
    v_batch.market_city,
    v_batch.supplier,
    v_batch.breed,
    v_batch.purchase_rate,
    v_batch.animal_count,
    v_batch.total_weight,
    v_batch.already_tagged,
    v_batch.notes,
    not v_locked,
    case
      when v_locked then
        'This batch is locked because at least one animal has already progressed to Induction, Shipment, or Mortality.'
      else null::text
    end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.correct_purchase_entry(p_tag text, p_new_tag text, p_new_purchase_weight numeric, p_market_city text, p_supplier text, p_breed text, p_purchase_rate numeric, p_notes text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_stored_tag text;
  v_new_tag text;
  v_duplicate_tag text;
  v_animal public.animals%rowtype;
  v_batch public.batches%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_count integer;
  v_total numeric;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(u.role))
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if coalesce(v_role, '') not in ('management', 'purchase') then
    raise exception 'Purchase or Management access required';
  end if;

  if nullif(btrim(p_tag), '') is null then
    raise exception 'Tag is required';
  end if;

  if nullif(btrim(p_new_tag), '') is null then
    raise exception 'Corrected Tag Number is required';
  end if;

  if not public.is_valid_configured_farm_tag(btrim(p_new_tag)) then
    raise exception
      'Invalid Tag Number %. Required format example: %',
      btrim(p_new_tag),
      public.build_farm_tag(1);
  end if;

  if p_new_purchase_weight is null or p_new_purchase_weight <= 0 then
    raise exception 'Purchase weight must be greater than zero';
  end if;

  if nullif(btrim(p_market_city), '') is null then
    raise exception 'Market / City is required';
  end if;

  if nullif(btrim(p_supplier), '') is null then
    raise exception 'Supplier / Buyer is required';
  end if;

  if nullif(btrim(p_breed), '') is null then
    raise exception 'Breed is required';
  end if;

  if p_purchase_rate is null or p_purchase_rate <= 0 then
    raise exception 'Purchase rate must be greater than zero';
  end if;

  if nullif(btrim(p_reason), '') is null
     or char_length(btrim(p_reason)) < 3 then
    raise exception 'Correction reason is required';
  end if;

  -- Serialize with new-tag generation / validation.
  perform pg_advisory_xact_lock(hashtext('farmflow_ff_tag_generation'));
  perform pg_advisory_xact_lock(hashtext('farmflow_purchase_correction'));

  v_stored_tag := public.resolve_animal_tag(btrim(p_tag));

  if v_stored_tag is null then
    raise exception 'Tag not found';
  end if;

  select a.*
    into v_animal
  from public.animals a
  where a.tag = v_stored_tag
  for update;

  if not found then
    raise exception 'Tag not found';
  end if;

  select b.*
    into v_batch
  from public.batches b
  where b.id = v_animal.batch_id
  for update;

  if not found then
    raise exception 'Purchase batch not found';
  end if;

  -- Lock all animals in the batch, then re-check the downstream guard.
  perform 1
  from public.animals a
  where a.batch_id = v_batch.id
  for update;

  if public.purchase_batch_has_downstream_activity(v_batch.id) then
    raise exception 'Purchase correction is locked because this batch has downstream activity';
  end if;

  v_new_tag := public.normalize_farm_tag(btrim(p_new_tag));

  if public.farm_tag_number(v_new_tag) is not null
     and public.farm_tag_number(v_new_tag) <= 0 then
    raise exception 'Invalid farm tag %', p_new_tag;
  end if;

  select a.tag
    into v_duplicate_tag
  from public.animals a
  where a.id <> v_animal.id
    and public.normalize_farm_tag(a.tag) = v_new_tag
  limit 1;

  if v_duplicate_tag is not null then
    raise exception 'Tag % already exists', v_duplicate_tag;
  end if;

  v_old_values := jsonb_build_object(
    'tag', v_animal.tag,
    'purchase_weight', v_animal.purchase_weight,
    'market_city', v_batch.market_city,
    'supplier', v_batch.supplier,
    'breed', v_batch.breed,
    'purchase_rate', v_batch.purchase_rate,
    'notes', v_batch.notes,
    'animal_count', v_batch.animal_count,
    'total_weight', v_batch.total_weight
  );

  if v_animal.tag is not distinct from v_new_tag
     and v_animal.purchase_weight is not distinct from p_new_purchase_weight
     and v_batch.market_city is not distinct from btrim(p_market_city)
     and v_batch.supplier is not distinct from btrim(p_supplier)
     and v_batch.breed is not distinct from btrim(p_breed)
     and v_batch.purchase_rate is not distinct from p_purchase_rate
     and v_batch.notes is not distinct from nullif(btrim(coalesce(p_notes, '')), '') then
    raise exception 'No purchase changes were made';
  end if;

  update public.animals
  set tag = v_new_tag,
      purchase_weight = p_new_purchase_weight
  where id = v_animal.id;

  update public.batches
  set market_city = btrim(p_market_city),
      supplier = btrim(p_supplier),
      breed = btrim(p_breed),
      purchase_rate = p_purchase_rate,
      notes = nullif(btrim(coalesce(p_notes, '')), '')
  where id = v_batch.id;

  select count(*), coalesce(sum(a.purchase_weight), 0)
    into v_count, v_total
  from public.animals a
  where a.batch_id = v_batch.id;

  update public.batches
  set animal_count = v_count,
      total_weight = v_total
  where id = v_batch.id;

  v_new_values := jsonb_build_object(
    'tag', v_new_tag,
    'purchase_weight', p_new_purchase_weight,
    'market_city', btrim(p_market_city),
    'supplier', btrim(p_supplier),
    'breed', btrim(p_breed),
    'purchase_rate', p_purchase_rate,
    'notes', nullif(btrim(coalesce(p_notes, '')), ''),
    'animal_count', v_count,
    'total_weight', v_total
  );

  insert into public.purchase_corrections (
    action,
    animal_id,
    batch_id,
    batch_code,
    old_values,
    new_values,
    reason,
    changed_by
  ) values (
    'edit',
    v_animal.id,
    v_batch.id,
    v_batch.batch_code,
    v_old_values,
    v_new_values,
    btrim(p_reason),
    v_user_id
  );

  return v_new_tag;
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_purchase_entry(p_tag text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_stored_tag text;
  v_animal public.animals%rowtype;
  v_batch public.batches%rowtype;
  v_old_values jsonb;
  v_count integer;
  v_total numeric;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(u.role))
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if coalesce(v_role, '') not in ('management', 'purchase') then
    raise exception 'Purchase or Management access required';
  end if;

  if nullif(btrim(p_tag), '') is null then
    raise exception 'Tag is required';
  end if;

  if nullif(btrim(p_reason), '') is null
     or char_length(btrim(p_reason)) < 3 then
    raise exception 'Deletion reason is required';
  end if;

  perform pg_advisory_xact_lock(hashtext('farmflow_ff_tag_generation'));
  perform pg_advisory_xact_lock(hashtext('farmflow_purchase_correction'));

  v_stored_tag := public.resolve_animal_tag(btrim(p_tag));

  if v_stored_tag is null then
    raise exception 'Tag not found';
  end if;

  select a.*
    into v_animal
  from public.animals a
  where a.tag = v_stored_tag
  for update;

  if not found then
    raise exception 'Tag not found';
  end if;

  select b.*
    into v_batch
  from public.batches b
  where b.id = v_animal.batch_id
  for update;

  if not found then
    raise exception 'Purchase batch not found';
  end if;

  perform 1
  from public.animals a
  where a.batch_id = v_batch.id
  for update;

  if public.purchase_batch_has_downstream_activity(v_batch.id) then
    raise exception 'Purchase deletion is locked because this batch has downstream activity';
  end if;

  v_old_values := jsonb_build_object(
    'tag', v_animal.tag,
    'purchase_weight', v_animal.purchase_weight,
    'market_city', v_batch.market_city,
    'supplier', v_batch.supplier,
    'breed', v_batch.breed,
    'purchase_rate', v_batch.purchase_rate,
    'notes', v_batch.notes,
    'animal_count', v_batch.animal_count,
    'total_weight', v_batch.total_weight,
    'purchase_date', v_batch.purchase_date
  );

  -- Audit first. animal_id/batch_id are intentionally stored as plain numeric
  -- snapshots rather than foreign keys so the audit survives a real delete.
  insert into public.purchase_corrections (
    action,
    animal_id,
    batch_id,
    batch_code,
    old_values,
    new_values,
    reason,
    changed_by
  ) values (
    'delete',
    v_animal.id,
    v_batch.id,
    v_batch.batch_code,
    v_old_values,
    null,
    btrim(p_reason),
    v_user_id
  );

  delete from public.animals
  where id = v_animal.id;

  select count(*), coalesce(sum(a.purchase_weight), 0)
    into v_count, v_total
  from public.animals a
  where a.batch_id = v_batch.id;

  if v_count = 0 then
    delete from public.batches
    where id = v_batch.id;

    return 'Deleted ' || v_animal.tag || '. Empty batch ' || v_batch.batch_code || ' was also removed.';
  end if;

  update public.batches
  set animal_count = v_count,
      total_weight = v_total
  where id = v_batch.id;

  return 'Deleted ' || v_animal.tag || ' from ' || v_batch.batch_code || '.';
end;
$function$;
