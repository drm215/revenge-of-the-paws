-- Weekly horde siege for Revenge of the Paws. Run once in the Supabase SQL editor (after supabase.sql).
-- Every zombie a signed-in player destroys adds points to the week's shared horde. Players can only
-- add their own hits and can't read the raw rows; siege_board() returns the totals and top 10.

create table if not exists public.siege_hits (
  id         bigint generated always as identity primary key,
  week       int not null,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  points     int not null check (points between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists siege_hits_week on public.siege_hits (week, user_id);

alter table public.siege_hits enable row level security;

drop policy if exists "add own hits" on public.siege_hits;
create policy "add own hits" on public.siege_hits
  for insert to authenticated with check (auth.uid() = user_id);

-- Totals for one week: damage dealt, packs taking part, your own damage, and the top 10 packs.
create or replace function public.siege_board(p_week int) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'total', coalesce((select sum(points) from siege_hits where week = p_week), 0),
    'players', (select count(distinct user_id) from siege_hits where week = p_week),
    'mine', coalesce((select sum(points) from siege_hits where week = p_week and user_id = auth.uid()), 0),
    'top', coalesce((select json_agg(t) from (
      select max(name) as name, sum(points) as points from siege_hits
      where week = p_week group by user_id order by sum(points) desc limit 10) t), '[]'::json)
  );
$$;

revoke all on function public.siege_board(int) from public;
grant execute on function public.siege_board(int) to anon, authenticated;
