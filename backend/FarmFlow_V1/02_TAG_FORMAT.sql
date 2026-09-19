-- FarmFlow V1 — tag format and normalization

CREATE OR REPLACE FUNCTION public.build_farm_tag(p_number bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_config public.farm_tag_config%rowtype;
  v_digits text;
begin
  if p_number is null or p_number < 1 then
    raise exception 'Tag number must be at least 1';
  end if;

  select *
    into v_config
  from public.farm_tag_config
  where id = 1;

  if not found then
    raise exception 'Tag format is not configured';
  end if;

  v_digits := p_number::text;
  if length(v_digits) < v_config.tag_min_digits then
    v_digits := lpad(v_digits, v_config.tag_min_digits, '0');
  end if;

  if v_config.tag_mode = 'numeric' then
    return v_digits;
  end if;

  return v_config.tag_prefix || v_config.tag_separator || v_digits;
end;
$function$;

CREATE OR REPLACE FUNCTION public.farm_tag_number(p_input text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_input text := btrim(coalesce(p_input, ''));
  v_config public.farm_tag_config%rowtype;
  v_rest text;
  v_digits text;
  v_prefix_len integer;
  v_sep_len integer;
begin
  if v_input = '' then
    return null;
  end if;

  select *
    into v_config
  from public.farm_tag_config
  where id = 1;

  if not found then
    raise exception 'Tag format is not configured';
  end if;

  if v_config.tag_mode = 'numeric' then
    if v_input !~ '^[0-9]+$' then
      return null;
    end if;

    v_digits := regexp_replace(v_input, '^0+', '');
    if v_digits = '' then
      v_digits := '0';
    end if;

    return v_digits::bigint;
  end if;

  v_prefix_len := char_length(v_config.tag_prefix);
  v_sep_len := char_length(v_config.tag_separator);

  if char_length(v_input) <= v_prefix_len + v_sep_len then
    return null;
  end if;

  if lower(left(v_input, v_prefix_len)) <> lower(v_config.tag_prefix) then
    return null;
  end if;

  if substring(v_input from v_prefix_len + 1 for v_sep_len)
     <> v_config.tag_separator then
    return null;
  end if;

  v_rest := substring(v_input from v_prefix_len + v_sep_len + 1);

  if v_rest !~ '^[0-9]+$' then
    return null;
  end if;

  v_digits := regexp_replace(v_rest, '^0+', '');
  if v_digits = '' then
    v_digits := '0';
  end if;

  return v_digits::bigint;
end;
$function$;

CREATE OR REPLACE FUNCTION public.normalize_farm_tag(p_input text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_input text := btrim(coalesce(p_input, ''));
  v_config public.farm_tag_config%rowtype;
  v_digits text;
  v_rest text;
  v_prefix_len integer;
  v_sep_len integer;
begin
  if v_input = '' then
    raise exception 'Tag is required';
  end if;

  select *
    into v_config
  from public.farm_tag_config
  where id = 1;

  if not found then
    raise exception 'Tag format is not configured';
  end if;

  if v_config.tag_mode = 'numeric' then
    if v_input !~ '^[0-9]+$' then
      return v_input;
    end if;

    v_digits := regexp_replace(v_input, '^0+', '');
    if v_digits = '' then
      v_digits := '0';
    end if;

    if length(v_digits) < v_config.tag_min_digits then
      v_digits := lpad(v_digits, v_config.tag_min_digits, '0');
    end if;

    return v_digits;
  end if;

  v_prefix_len := char_length(v_config.tag_prefix);
  v_sep_len := char_length(v_config.tag_separator);

  if char_length(v_input) <= v_prefix_len + v_sep_len then
    return v_input;
  end if;

  if lower(left(v_input, v_prefix_len)) <> lower(v_config.tag_prefix) then
    return v_input;
  end if;

  if substring(v_input from v_prefix_len + 1 for v_sep_len) <> v_config.tag_separator then
    return v_input;
  end if;

  v_rest := substring(v_input from v_prefix_len + v_sep_len + 1);
  if v_rest !~ '^[0-9]+$' then
    return v_input;
  end if;

  v_digits := regexp_replace(v_rest, '^0+', '');
  if v_digits = '' then
    v_digits := '0';
  end if;

  if length(v_digits) < v_config.tag_min_digits then
    v_digits := lpad(v_digits, v_config.tag_min_digits, '0');
  end if;

  return v_config.tag_prefix || v_config.tag_separator || v_digits;
end;
$function$;

CREATE OR REPLACE FUNCTION public.is_valid_configured_farm_tag(p_input text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_input text := btrim(coalesce(p_input, ''));
  v_config public.farm_tag_config%rowtype;
  v_digits text;
  v_prefix_len integer;
  v_sep_len integer;
begin
  if v_input = '' then
    return false;
  end if;

  select *
    into v_config
  from public.farm_tag_config
  where id = 1;

  if not found then
    raise exception 'Tag format is not configured';
  end if;

  ------------------------------------------------------------
  -- Numeric-only farm mode
  ------------------------------------------------------------
  if v_config.tag_mode = 'numeric' then
    if v_input !~ '^[0-9]+$' then
      return false;
    end if;

    -- Zero is never a valid farm tag number.
    v_digits := regexp_replace(v_input, '^0+', '');
    return v_digits <> '';
  end if;

  ------------------------------------------------------------
  -- Prefixed farm mode
  ------------------------------------------------------------
  v_prefix_len := char_length(v_config.tag_prefix);
  v_sep_len := char_length(v_config.tag_separator);

  -- Must contain configured prefix + separator + at least one suffix character.
  if char_length(v_input) <= v_prefix_len + v_sep_len then
    return false;
  end if;

  -- Prefix is logically case-insensitive.
  if lower(left(v_input, v_prefix_len)) <> lower(v_config.tag_prefix) then
    return false;
  end if;

  -- Separator is exact.
  if substring(v_input from v_prefix_len + 1 for v_sep_len)
       <> v_config.tag_separator then
    return false;
  end if;

  v_digits := substring(v_input from v_prefix_len + v_sep_len + 1);

  -- Suffix must be digits only.
  if v_digits !~ '^[0-9]+$' then
    return false;
  end if;

  -- Zero is never a valid farm tag number.
  if regexp_replace(v_digits, '^0+', '') = '' then
    return false;
  end if;

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_animal_tag(p_input text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_normalized text;
  v_result text;
  v_count integer;
begin
  v_normalized := public.normalize_farm_tag(p_input);

  select count(*), min(a.tag)
    into v_count, v_result
  from public.animals a
  where public.normalize_farm_tag(a.tag) = v_normalized;

  if v_count > 1 then
    raise exception 'Multiple animals share the same logical tag identity';
  end if;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.max_used_farm_tag_number()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select greatest(
    coalesce((
      select max(public.farm_tag_number(a.tag))
      from public.animals a
    ), 0),
    coalesce((
      select max(public.farm_tag_number(pc.old_values->>'tag'))
      from public.purchase_corrections pc
    ), 0),
    coalesce((
      select max(public.farm_tag_number(pc.new_values->>'tag'))
      from public.purchase_corrections pc
      where pc.new_values is not null
    ), 0)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_farm_tag_config()
 RETURNS TABLE(configured boolean, tag_mode text, tag_prefix text, tag_separator text, tag_min_digits integer, example_tag text, is_locked boolean, operational_rows bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_config public.farm_tag_config%rowtype;
  v_locked boolean;
  v_rows bigint;
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
    raise exception 'Management access required';
  end if;

  select
    (exists(select 1 from public.animals)
      or exists(select 1 from public.batches)
      or exists(select 1 from public.shipments)),
    ((select count(*) from public.animals)
      + (select count(*) from public.batches)
      + (select count(*) from public.shipments))
  into v_locked, v_rows;

  select *
    into v_config
  from public.farm_tag_config
  where id = 1;

  if not found then
    return query
    select
      false,
      null::text,
      null::text,
      null::text,
      6,
      null::text,
      v_locked,
      v_rows;
    return;
  end if;

  return query
  select
    true,
    v_config.tag_mode,
    v_config.tag_prefix,
    v_config.tag_separator,
    v_config.tag_min_digits,
    case
      when v_config.tag_mode = 'numeric' then
        lpad('1', v_config.tag_min_digits, '0')
      else
        v_config.tag_prefix || v_config.tag_separator ||
        lpad('1', v_config.tag_min_digits, '0')
    end,
    v_locked,
    v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_farm_tag_config(p_tag_mode text, p_tag_prefix text DEFAULT NULL::text, p_tag_separator text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_mode text := lower(btrim(coalesce(p_tag_mode, '')));
  v_prefix text;
  v_separator text;
  v_existing public.farm_tag_config%rowtype;
  v_has_existing boolean := false;
  v_locked boolean;
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
    raise exception 'Management access required';
  end if;

  if v_mode not in ('prefixed', 'numeric') then
    raise exception 'Choose Prefix + Number or Numeric Only';
  end if;

  if v_mode = 'prefixed' then
    v_prefix := btrim(coalesce(p_tag_prefix, ''));
    v_separator := coalesce(p_tag_separator, '');

    if v_prefix !~ '^[A-Za-z][A-Za-z0-9]{0,11}$' then
      raise exception 'Prefix must start with a letter and contain only letters/numbers (max 12 characters)';
    end if;

    if v_separator not in ('-', '@', '/', '_', '.', '#', ':') then
      raise exception 'Choose a supported separator';
    end if;
  else
    v_prefix := null;
    v_separator := null;
  end if;

  select *
    into v_existing
  from public.farm_tag_config
  where id = 1;

  v_has_existing := found;

  select
    exists(select 1 from public.animals)
    or exists(select 1 from public.batches)
    or exists(select 1 from public.shipments)
  into v_locked;

  if v_locked then
    if not v_has_existing then
      raise exception 'Tag format cannot be configured while operational data exists. Reset operational data first.';
    end if;

    -- Re-saving exactly the same configuration is harmless.
    if v_existing.tag_mode = v_mode
       and coalesce(v_existing.tag_prefix, '') = coalesce(v_prefix, '')
       and coalesce(v_existing.tag_separator, '') = coalesce(v_separator, '')
       and v_existing.tag_min_digits = 6 then
      return;
    end if;

    raise exception 'Tag format is locked while operational data exists. Start from zero before changing it.';
  end if;

  insert into public.farm_tag_config (
    id,
    tag_mode,
    tag_prefix,
    tag_separator,
    tag_min_digits,
    configured_by,
    configured_at,
    updated_at
  ) values (
    1,
    v_mode,
    v_prefix,
    v_separator,
    6,
    v_user_id,
    now(),
    now()
  )
  on conflict (id) do update
  set tag_mode = excluded.tag_mode,
      tag_prefix = excluded.tag_prefix,
      tag_separator = excluded.tag_separator,
      tag_min_digits = 6,
      configured_by = excluded.configured_by,
      updated_at = now();
end;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_configured_farm_tag()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_example text;
begin
  if tg_op = 'INSERT' or new.tag is distinct from old.tag then
    if not public.is_valid_configured_farm_tag(new.tag) then
      v_example := public.build_farm_tag(1);
      raise exception 'Invalid Tag Number %. Use the configured farm format, for example %',
        coalesce(new.tag, ''), v_example;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists animals_enforce_configured_farm_tag on public.animals;
create trigger animals_enforce_configured_farm_tag
before insert or update on public.animals
for each row execute function public.enforce_configured_farm_tag();
