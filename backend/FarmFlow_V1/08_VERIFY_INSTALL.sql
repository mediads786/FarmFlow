-- FarmFlow V1 — post-install verification
select table_name
from information_schema.tables
where table_schema='public' and table_type='BASE TABLE'
order by table_name;

select routine_name
from information_schema.routines
where routine_schema='public'
order by routine_name;

select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname='public'
order by tablename, policyname;

select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
order by c.relname;

select trigger_name, event_manipulation, action_timing, action_statement
from information_schema.triggers
where trigger_schema='public'
order by event_object_table, trigger_name, event_manipulation;
