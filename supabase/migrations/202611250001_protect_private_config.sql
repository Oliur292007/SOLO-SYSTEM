-- Keep the WhatsApp number private while preserving the app's public config RPC.
-- The mobile app reads configuration through get_config(); it does not use whatsapp_number.

begin;

-- Remove direct table access for public app roles. The app must use the filtered RPC below.
drop policy if exists "Config public read" on public.config;
revoke all privileges on table public.config from anon, authenticated;

-- Run as the function owner so callers do not need direct table permissions.
-- A fixed search_path and fully-qualified table reference prevent object shadowing.
create or replace function public.get_config()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
  select coalesce(
    pg_catalog.jsonb_object_agg(c.key, c.value)
      filter (where c.key <> 'whatsapp_number'),
    '{}'::jsonb
  )
  from public.config as c;
$function$;

-- Explicitly expose only this filtered read operation to app roles.
revoke all on function public.get_config() from public, anon, authenticated;
grant execute on function public.get_config() to anon, authenticated;

commit;
