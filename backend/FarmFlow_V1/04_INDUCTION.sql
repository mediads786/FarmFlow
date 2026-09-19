-- FarmFlow V1 — induction

CREATE OR REPLACE FUNCTION public.get_pending_induction(p_batch_code text)
 RETURNS TABLE(tag text, purchase_weight numeric, purchase_date date)
 LANGUAGE sql
AS $function$
  select
    a.tag,
    a.purchase_weight,
    b.purchase_date
  from public.animals a
  join public.batches b
    on b.id = a.batch_id
  where b.batch_code = p_batch_code
    and a.induction_weight is null
  order by a.tag;
$function$;

CREATE OR REPLACE FUNCTION public.save_induction(p_entries jsonb)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_item jsonb;
  v_tag text;
  v_weight numeric;
  v_date date;
  v_saved integer := 0;
  v_bad_tag text;
begin

  if p_entries is null
     or jsonb_typeof(p_entries) <> 'array'
     or jsonb_array_length(p_entries) = 0 then
    raise exception 'At least one induction entry is required';
  end if;

  -- STRICT canonical tag validation BEFORE any write.
  select trim(x->>'tag')
    into v_bad_tag
  from jsonb_array_elements(p_entries) x
  where nullif(trim(x->>'tag'), '') is null
     or not public.is_valid_configured_farm_tag(trim(x->>'tag'))
  limit 1;

  if v_bad_tag is not null then
    raise exception
      'Invalid Tag Number %. Required format example: %',
      v_bad_tag,
      public.build_farm_tag(1);
  end if;

  -- No logical duplicate tags in same submission.
  if (
    select count(*)
    from jsonb_array_elements(p_entries)
  ) <> (
    select count(distinct public.normalize_farm_tag(trim(x->>'tag')))
    from jsonb_array_elements(p_entries) x
  ) then
    raise exception 'Duplicate tags found in induction entry';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_entries)
  loop

    v_tag := public.normalize_farm_tag(trim(v_item->>'tag'));
    v_weight := nullif(v_item->>'induction_weight', '')::numeric;
    v_date := nullif(v_item->>'induction_date', '')::date;

    if v_date is null then
      raise exception
        'Induction date is required for Tag %',
        v_tag;
    end if;

    if v_weight is null or v_weight <= 0 then
      raise exception
        'Invalid induction weight for Tag %',
        v_tag;
    end if;

    if not exists (
      select 1
      from public.animals
      where tag = v_tag
    ) then
      raise exception 'Tag % not found', v_tag;
    end if;

    if exists (
      select 1
      from public.animals
      where tag = v_tag
        and induction_weight is not null
    ) then
      raise exception 'Tag % is already inducted', v_tag;
    end if;

    update public.animals
    set
      induction_weight = v_weight,
      induction_date = v_date,
      status = 'inducted'
    where tag = v_tag;

    v_saved := v_saved + 1;

  end loop;

  return v_saved;
end;
$function$;

CREATE OR REPLACE FUNCTION public.correct_induction(p_tag text, p_new_weight numeric, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_animal public.animals%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select u.role
    into v_role
  from public.users u
  where u.id = v_user_id
    and u.active is true;

  if v_role is distinct from 'management' then
    raise exception 'Only Management can correct induction weights';
  end if;

  if nullif(btrim(p_tag), '') is null then
    raise exception 'Tag is required';
  end if;

  if p_new_weight is null or p_new_weight < 1 then
    raise exception 'Induction weight must be at least 1 kg';
  end if;

  if nullif(btrim(p_reason), '') is null
     or char_length(btrim(p_reason)) < 3 then
    raise exception 'Correction reason is required';
  end if;

  select a.*
    into v_animal
  from public.animals a
  where a.tag = btrim(p_tag)
  for update;

  if not found then
    raise exception 'Tag not found';
  end if;

  if v_animal.induction_weight is null then
    raise exception 'This animal has no recorded induction weight to correct';
  end if;

  if v_animal.induction_weight = p_new_weight then
    raise exception 'Corrected weight must be different from the current weight';
  end if;

  insert into public.induction_corrections (
    animal_id,
    tag,
    old_weight,
    new_weight,
    induction_date,
    reason,
    changed_by
  ) values (
    v_animal.id,
    v_animal.tag,
    v_animal.induction_weight,
    p_new_weight,
    v_animal.induction_date,
    btrim(p_reason),
    v_user_id
  );

  update public.animals
  set induction_weight = p_new_weight
  where id = v_animal.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_induction_report(p_batch_code text DEFAULT NULL::text, p_purchase_date date DEFAULT NULL::date)
 RETURNS TABLE(tag text, batch_code text, purchase_weight numeric, induction_weight numeric, weight_difference numeric, induction_date date)
 LANGUAGE sql
AS $function$
  select
    a.tag,
    b.batch_code,
    a.purchase_weight,
    a.induction_weight,
    case
      when a.induction_weight is null then null
      else a.induction_weight - a.purchase_weight
    end as weight_difference,
    a.induction_date
  from public.animals a
  join public.batches b
    on b.id = a.batch_id
  where
    (p_batch_code is null or b.batch_code = p_batch_code)
    and
    (p_purchase_date is null or b.purchase_date = p_purchase_date)
  order by a.tag;
$function$;

CREATE OR REPLACE FUNCTION public.get_induction_report_v2(p_mode text, p_batch_code text DEFAULT NULL::text, p_from_batch text DEFAULT NULL::text, p_to_batch text DEFAULT NULL::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(tag text, batch_code text, purchase_date date, purchase_weight numeric, induction_weight numeric, difference numeric, induction_date date, induction_status text)
 LANGUAGE plpgsql
AS $function$
begin

  -- ---------------------------------------------------------
  -- Validate requested report mode
  -- ---------------------------------------------------------
  if p_mode not in (
    'single_batch',
    'batch_range',
    'date_range',
    'all'
  ) then
    raise exception
      'Report mode must be single_batch, batch_range, date_range, or all';
  end if;


  -- ---------------------------------------------------------
  -- Single Batch validation
  -- ---------------------------------------------------------
  if p_mode = 'single_batch' then
    if nullif(trim(p_batch_code), '') is null then
      raise exception 'Batch ID is required';
    end if;
  end if;


  -- ---------------------------------------------------------
  -- Batch Range validation
  -- ---------------------------------------------------------
  if p_mode = 'batch_range' then
    if nullif(trim(p_from_batch), '') is null
       or nullif(trim(p_to_batch), '') is null then
      raise exception 'From Batch and To Batch are required';
    end if;

    if regexp_replace(p_from_batch, '[^0-9]', '', 'g') = ''
       or regexp_replace(p_to_batch, '[^0-9]', '', 'g') = '' then
      raise exception 'Invalid batch range';
    end if;

    if regexp_replace(
         p_from_batch,
         '[^0-9]',
         '',
         'g'
       )::bigint
       >
       regexp_replace(
         p_to_batch,
         '[^0-9]',
         '',
         'g'
       )::bigint then
      raise exception 'From Batch cannot be greater than To Batch';
    end if;
  end if;


  -- ---------------------------------------------------------
  -- Date Range validation
  -- ---------------------------------------------------------
  if p_mode = 'date_range' then
    if p_from_date is null or p_to_date is null then
      raise exception 'From Date and To Date are required';
    end if;

    if p_from_date > p_to_date then
      raise exception 'From Date cannot be greater than To Date';
    end if;
  end if;


  -- ---------------------------------------------------------
  -- Return every animal belonging to the selected purchase
  -- scope.
  --
  -- IMPORTANT:
  -- This deliberately DOES NOT filter by current animal status,
  -- shipment_id or mortality_date.
  --
  -- Therefore historical batch totals remain reconcilable even
  -- after an animal is shipped or dies later.
  -- ---------------------------------------------------------
  return query
  select
    a.tag,
    b.batch_code,
    b.purchase_date,
    a.purchase_weight,
    a.induction_weight,

    case
      when a.induction_weight is null then null
      else a.induction_weight - a.purchase_weight
    end as difference,

    a.induction_date,

    case
      when a.induction_weight is null then 'Pending'
      else 'Completed'
    end as induction_status

  from public.animals a

  join public.batches b
    on b.id = a.batch_id

  where

    -- Single Batch
    (
      p_mode = 'single_batch'
      and upper(trim(b.batch_code))
          = upper(trim(p_batch_code))
    )

    or

    -- Batch Range
    (
      p_mode = 'batch_range'
      and regexp_replace(
            b.batch_code,
            '[^0-9]',
            '',
            'g'
          )::bigint
          between
          regexp_replace(
            p_from_batch,
            '[^0-9]',
            '',
            'g'
          )::bigint
          and
          regexp_replace(
            p_to_batch,
            '[^0-9]',
            '',
            'g'
          )::bigint
    )

    or

    -- Date Range
    (
      p_mode = 'date_range'
      and b.purchase_date
          between p_from_date and p_to_date
    )

    or

    -- Complete history
    (
      p_mode = 'all'
    )

  order by
    regexp_replace(
      b.batch_code,
      '[^0-9]',
      '',
      'g'
    )::bigint,
    a.id;

end;
$function$;
