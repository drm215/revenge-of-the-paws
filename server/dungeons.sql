-- Dungeon leaderboards for Revenge of the Paws: each pack's deepest wave in each region's dungeon.
-- Run in the Supabase SQL editor after supabase.sql; safe to run again.
-- Players can only raise their own record (record_dungeon) and can't read the table directly;
-- dungeon_board() returns a region's top 10 and your own best. Names are pet and region, never towns.

create table if not exists public.dungeon_records (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  region     text not null check (char_length(region) between 1 and 40),
  name       text not null check (char_length(name) between 1 and 40),
  best       int not null check (best between 1 and 1000),
  updated_at timestamptz not null default now(),
  primary key (user_id, region)
);

create index if not exists dungeon_records_board on public.dungeon_records (region, best desc);

alter table public.dungeon_records enable row level security;

-- Records only go up.
create or replace function public.record_dungeon(p_region text, p_wave int, p_name text) returns void
language sql security definer set search_path = public as $$
  insert into dungeon_records (user_id, region, name, best) values (auth.uid(), p_region, p_name, p_wave)
  on conflict (user_id, region) do update
    set best = greatest(dungeon_records.best, excluded.best), name = excluded.name, updated_at = now();
$$;

create or replace function public.dungeon_board(p_region text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'mine', coalesce((select best from dungeon_records where region = p_region and user_id = auth.uid()), 0),
    'top', coalesce((select json_agg(t) from (
      select name, best from dungeon_records where region = p_region order by best desc, updated_at limit 10) t), '[]'::json)
  );
$$;

revoke all on function public.record_dungeon(text, int, text) from public, anon;
grant execute on function public.record_dungeon(text, int, text) to authenticated;
revoke all on function public.dungeon_board(text) from public;
grant execute on function public.dungeon_board(text) to anon, authenticated;
