-- FarmFlow V1 — shipments, mortality, inventory, dashboard and reporting

CREATE OR REPLACE FUNCTION public.create_shipment(p_shipment_date date, p_animal_count integer, p_meat_rate numeric, p_offal_rate numeric, p_entries jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  v_shipment_id bigint;
  v_shipment_code text;

  v_item jsonb;
  v_tag text;
  v_out_weight numeric;
  v_meat_weight numeric;

  v_animal_id bigint;
  v_actual_count integer;
  v_bad_tag text;
begin

  if p_shipment_date is null then
    raise exception 'Shipment date is required';
  end if;

  if p_animal_count <= 0 then
    raise exception 'Animal count must be greater than zero';
  end if;

  if p_meat_rate <= 0 then
    raise exception 'Meat rate must be greater than zero';
  end if;

  if p_offal_rate < 0 then
    raise exception 'Offal rate cannot be negative';
  end if;

  if p_entries is null
     or jsonb_typeof(p_entries) <> 'array'
     or jsonb_array_length(p_entries) = 0 then
    raise exception 'Shipment animals are required';
  end if;

  -- Declared animal count must match entered animals.
  select count(*)
  into v_actual_count
  from jsonb_array_elements(p_entries);

  if v_actual_count <> p_animal_count then
    raise exception
      'Animal count mismatch. Declared %, entered %',
      p_animal_count,
      v_actual_count;
  end if;

  -- STRICT canonical tag validation BEFORE creating the shipment header.
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

  -- No logical duplicate tags inside same submission.
  if (
    select count(*)
    from jsonb_array_elements(p_entries)
  ) <> (
    select count(distinct public.normalize_farm_tag(trim(x->>'tag')))
    from jsonb_array_elements(p_entries) x
  ) then
    raise exception 'Duplicate tags found in shipment';
  end if;

  -- Create shipment header. Any later exception rolls back this transaction.
  insert into public.shipments (
    shipment_date,
    animal_count,
    meat_rate,
    offal_rate,
    created_by
  )
  values (
    p_shipment_date,
    p_animal_count,
    p_meat_rate,
    p_offal_rate,
    auth.uid()
  )
  returning id, shipment_code
  into v_shipment_id, v_shipment_code;

  -- Process each animal.
  for v_item in
    select value
    from jsonb_array_elements(p_entries)
  loop

    v_tag := public.normalize_farm_tag(trim(v_item->>'tag'));
    v_out_weight := nullif(v_item->>'out_weight', '')::numeric;
    v_meat_weight := nullif(v_item->>'meat_weight', '')::numeric;

    if v_out_weight is null or v_out_weight <= 0 then
      raise exception
        'Invalid Out/Live Weight for Tag %',
        v_tag;
    end if;

    if v_meat_weight is null or v_meat_weight <= 0 then
      raise exception
        'Invalid Meat Weight for Tag %',
        v_tag;
    end if;

    if v_meat_weight > v_out_weight then
      raise exception
        'Meat Weight cannot exceed Live Weight for Tag %',
        v_tag;
    end if;

    select id
    into v_animal_id
    from public.animals
    where tag = v_tag;

    if v_animal_id is null then
      raise exception 'Tag % not found', v_tag;
    end if;

    -- Induction is NOT required for Animal Out / Shipment.
    if exists (
      select 1
      from public.animals
      where id = v_animal_id
        and shipment_id is not null
    ) then
      raise exception
        'Tag % has already been shipped',
        v_tag;
    end if;

    if exists (
      select 1
      from public.animals
      where id = v_animal_id
        and (
          mortality_date is not null
          or lower(coalesce(status, '')) in ('mortality', 'dead')
        )
    ) then
      raise exception
        'Tag % is already recorded as mortality',
        v_tag;
    end if;

    update public.animals
    set
      out_weight = v_out_weight,
      meat_weight = v_meat_weight,
      shipment_id = v_shipment_id,
      status = 'shipped'
    where id = v_animal_id;

  end loop;

  return v_shipment_code;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_shipments(p_search_mode text, p_from_shipment text DEFAULT NULL::text, p_to_shipment text DEFAULT NULL::text, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(shipment_code text, shipment_date date, animal_count integer, meat_rate numeric, offal_rate numeric, daily_feed_cost numeric)
 LANGUAGE plpgsql
AS $function$
begin

  if p_search_mode not in ('shipment', 'date') then
    raise exception
      'Search mode must be shipment or date';
  end if;

  if p_search_mode = 'shipment' then

    return query
    select
      s.shipment_code,
      s.shipment_date,
      s.animal_count,
      s.meat_rate,
      s.offal_rate,
      s.daily_feed_cost
    from public.shipments s
    where
      (
        p_from_shipment is null
        or regexp_replace(
          s.shipment_code,
          '[^0-9]',
          '',
          'g'
        )::integer
        >=
        regexp_replace(
          p_from_shipment,
          '[^0-9]',
          '',
          'g'
        )::integer
      )
      and
      (
        p_to_shipment is null
        or regexp_replace(
          s.shipment_code,
          '[^0-9]',
          '',
          'g'
        )::integer
        <=
        regexp_replace(
          p_to_shipment,
          '[^0-9]',
          '',
          'g'
        )::integer
      )
    order by s.id;

  else

    return query
    select
      s.shipment_code,
      s.shipment_date,
      s.animal_count,
      s.meat_rate,
      s.offal_rate,
      s.daily_feed_cost
    from public.shipments s
    where
      (p_from_date is null or s.shipment_date >= p_from_date)
      and
      (p_to_date is null or s.shipment_date <= p_to_date)
    order by s.shipment_date, s.id;

  end if;

end;
$function$;

CREATE OR REPLACE FUNCTION public.set_shipment_feed_cost(p_shipment_code text, p_daily_feed_cost numeric)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
declare
  v_existing numeric;
begin

  if p_daily_feed_cost <= 0 then
    raise exception 'Daily feed cost must be greater than zero';
  end if;

  select daily_feed_cost
  into v_existing
  from public.shipments
  where shipment_code = p_shipment_code;

  if not found then
    raise exception 'Shipment % not found', p_shipment_code;
  end if;

  if v_existing is not null then
    raise exception
      'Daily feed cost is already saved for Shipment %',
      p_shipment_code;
  end if;

  update public.shipments
  set daily_feed_cost = p_daily_feed_cost
  where shipment_code = p_shipment_code;

  return p_daily_feed_cost;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_shipment_pl(p_shipment_code text)
 RETURNS TABLE(tag text, shipment_date date, days_at_farm integer, buying_weight numeric, buying_rate numeric, initial_cost numeric, daily_feed_cost numeric, feed_cost numeric, out_weight numeric, meat_weight numeric, meat_rate numeric, offal_rate numeric, dressing_percent numeric, grams_per_day numeric, income numeric, total_cost numeric, profit_loss numeric)
 LANGUAGE sql
AS $function$
  select
    a.tag,
    s.shipment_date,

    (s.shipment_date - b.purchase_date + 1)::integer,

    a.purchase_weight,
    b.purchase_rate,

    round(a.purchase_weight * b.purchase_rate, 2),

    s.daily_feed_cost,

    round(
      (s.shipment_date - b.purchase_date + 1)
      * s.daily_feed_cost,
      2
    ),

    a.out_weight,
    a.meat_weight,
    s.meat_rate,
    s.offal_rate,

    round(
      (a.meat_weight / nullif(a.out_weight, 0)) * 100,
      2
    ),

    round(
      (
        (a.out_weight - a.purchase_weight)
        /
        nullif(
          (s.shipment_date - b.purchase_date + 1),
          0
        )
      ) * 1000,
      2
    ),

    round(
      (a.meat_weight * s.meat_rate)
      + s.offal_rate,
      2
    ),

    round(
      (a.purchase_weight * b.purchase_rate)
      +
      (
        (s.shipment_date - b.purchase_date + 1)
        * s.daily_feed_cost
      ),
      2
    ),

    round(
      (
        (a.meat_weight * s.meat_rate)
        + s.offal_rate
      )
      -
      (
        (a.purchase_weight * b.purchase_rate)
        +
        (
          (s.shipment_date - b.purchase_date + 1)
          * s.daily_feed_cost
        )
      ),
      2
    )

  from public.animals a
  join public.shipments s
    on s.id = a.shipment_id
  join public.batches b
    on b.id = a.batch_id

  where s.shipment_code = p_shipment_code

  order by a.tag;
$function$;

CREATE OR REPLACE FUNCTION public.get_shipment_pl_summary(p_shipment_code text)
 RETURNS TABLE(shipment_code text, shipment_date date, animals integer, daily_feed_cost numeric, total_initial_cost numeric, total_feed_cost numeric, total_income numeric, total_cost numeric, net_profit_loss numeric, avg_profit_loss_per_animal numeric)
 LANGUAGE sql
AS $function$
  select
    p_shipment_code,
    max(x.shipment_date),
    count(*)::integer,
    max(x.daily_feed_cost),
    round(sum(x.initial_cost), 2),
    round(sum(x.feed_cost), 2),
    round(sum(x.income), 2),
    round(sum(x.total_cost), 2),
    round(sum(x.profit_loss), 2),
    round(avg(x.profit_loss), 2)

  from public.get_shipment_pl(p_shipment_code) x;
$function$;

CREATE OR REPLACE FUNCTION public.record_mortality(p_tag text, p_mortality_date date)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  v_animal_id bigint;
  v_tag text;
begin

  if nullif(trim(p_tag), '') is null then
    raise exception 'Tag is required';
  end if;

  if not public.is_valid_configured_farm_tag(trim(p_tag)) then
    raise exception
      'Invalid Tag Number %. Required format example: %',
      trim(p_tag),
      public.build_farm_tag(1);
  end if;

  if p_mortality_date is null then
    raise exception 'Mortality date is required';
  end if;

  v_tag := public.normalize_farm_tag(trim(p_tag));

  select id
  into v_animal_id
  from public.animals
  where tag = v_tag;

  if v_animal_id is null then
    raise exception 'Tag % not found', v_tag;
  end if;

  if exists (
    select 1
    from public.animals
    where id = v_animal_id
      and shipment_id is not null
  ) then
    raise exception 'Tag % has already been shipped', v_tag;
  end if;

  if exists (
    select 1
    from public.animals
    where id = v_animal_id
      and status = 'mortality'
  ) then
    raise exception 'Tag % is already recorded as mortality', v_tag;
  end if;

  update public.animals
  set
    mortality_date = p_mortality_date,
    status = 'mortality'
  where id = v_animal_id;

  return v_tag;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_live_inventory()
 RETURNS TABLE(tag text, batch_code text, breed text, purchase_date date, induction_date date, purchase_weight numeric, induction_weight numeric, days_at_farm integer, status text)
 LANGUAGE sql
AS $function$
  select
    a.tag,
    b.batch_code,
    b.breed,
    b.purchase_date,
    a.induction_date,
    a.purchase_weight,
    a.induction_weight,
    (
      (now() at time zone 'Asia/Karachi')::date
      - b.purchase_date
      + 1
    )::integer as days_at_farm,
    a.status
  from public.animals a
  join public.batches b
    on b.id = a.batch_id
  where a.status not in ('shipped', 'sold', 'mortality')
  order by b.purchase_date, a.tag;
$function$;

CREATE OR REPLACE FUNCTION public.get_dashboard_summary()
 RETURNS TABLE(standing_animals bigint, avg_days_at_farm integer, avg_dwg numeric, ready_for_shipment bigint, pending_induction bigint, low_dwg bigint, over_90_days bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with inventory as (
    select to_jsonb(x) as j
    from public.get_live_inventory() x
  ),
  normalized as (
    select
      coalesce(
        nullif(j->>'days_at_farm', '')::numeric,
        nullif(j->>'days', '')::numeric,
        nullif(j->>'days_on_farm', '')::numeric,
        0
      ) as days_at_farm,

      coalesce(
        nullif(j->>'dwg', '')::numeric,
        nullif(j->>'daily_weight_gain', '')::numeric,
        nullif(j->>'avg_dwg', '')::numeric
      ) as dwg,

      nullif(j->>'induction_weight', '')::numeric as induction_weight,

      regexp_replace(
        lower(
          trim(
            coalesce(
              j->>'inventory_status',
              j->>'status',
              ''
            )
          )
        ),
        '[_-]+',
        ' ',
        'g'
      ) as status_key
    from inventory
  ),
  classified as (
    select
      *,
      case
        when induction_weight is null then 'Pending Induction'
        when status_key in ('ready', 'ready for shipment') then 'Ready'
        when status_key in ('low dwg', 'low growth') then 'Low DWG'
        when status_key in ('over 90 days', 'over90days') then 'Over 90 Days'
        else 'Normal'
      end as normalized_status
    from normalized
  )
  select
    count(*)::bigint,

    coalesce(
      round(avg(days_at_farm)),
      0
    )::integer,

    coalesce(
      round(
        avg(dwg) filter (where dwg is not null),
        2
      ),
      0
    )::numeric,

    count(*) filter (
      where normalized_status = 'Ready'
    )::bigint,

    count(*) filter (
      where induction_weight is null
    )::bigint,

    count(*) filter (
      where normalized_status = 'Low DWG'
    )::bigint,

    count(*) filter (
      where days_at_farm > 90
    )::bigint
  from classified;
$function$;

CREATE OR REPLACE FUNCTION public.get_recent_activity_line(p_position integer)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$

  WITH activities AS (

    SELECT
      shipment_date AS activity_date,
      id AS sort_id,
      1 AS source_order,
      'Shipment ' || shipment_code || ' completed' AS activity_text
    FROM public.shipments
    WHERE shipment_date IS NOT NULL

    UNION ALL

    SELECT
      purchase_date AS activity_date,
      id AS sort_id,
      2 AS source_order,
      CASE
        WHEN nullif(trim(market_city), '') IS NOT NULL
          THEN 'Batch ' || batch_code || ' received from ' || trim(market_city)
        ELSE
          'Batch ' || batch_code || ' received'
      END AS activity_text
    FROM public.batches
    WHERE purchase_date IS NOT NULL

    UNION ALL

    SELECT
      mortality_date AS activity_date,
      id AS sort_id,
      3 AS source_order,
      'Mortality recorded: Tag ' || tag AS activity_text
    FROM public.animals
    WHERE mortality_date IS NOT NULL
  )

  SELECT coalesce(
    (
      SELECT activity_text
      FROM activities
      ORDER BY
        activity_date DESC,
        source_order ASC,
        sort_id DESC
      OFFSET greatest(p_position - 1, 0)
      LIMIT 1
    ),
    '—'
  );

$function$;
