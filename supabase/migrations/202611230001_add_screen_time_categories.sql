-- Screen Time categories are separate from Study Protection whitelist status.
-- NULL means use Android's automatic category detection.
alter table public.whitelist
  add column if not exists screen_time_category text;

alter table public.whitelist
  drop constraint if exists whitelist_screen_time_category_check;

alter table public.whitelist
  add constraint whitelist_screen_time_category_check
  check (
    screen_time_category is null
    or screen_time_category in ('social_media', 'game', 'education', 'excluded')
  );

insert into public.config(key, value)
values
  ('social_media_daily_limit_minutes', '240'),
  ('games_daily_limit_minutes', '120'),
  ('youtube_warning_interval_minutes', '5')
on conflict (key) do nothing;

update public.whitelist
set screen_time_category = 'social_media'
where package_name = 'com.whatsapp'
  and screen_time_category is null;

create or replace function public.get_whitelist()
returns jsonb
language sql
set search_path to 'public'
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'package_name', package_name,
        'app_name', app_name,
        'category', category,
        'screen_time_category', screen_time_category
      )
    ),
    '[]'::jsonb
  )
  from public.whitelist;
$function$;
