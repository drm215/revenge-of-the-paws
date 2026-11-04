-- Battle log for Revenge of the Paws: a report of every finished fight, for balancing.
-- Run once in the Supabase SQL editor (after supabase.sql). Safe to run again.
-- Signed-in players add their own reports. Reports hold no names, emails or account ids, and
-- recent_battles() hands them out without the account id, so balance checks can read them.

create table if not exists public.battle_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  legend     text not null default '' check (char_length(legend) <= 40),
  outcome    text not null default '' check (char_length(outcome) <= 20),
  players    int not null default 1 check (players between 1 and 4),
  report     jsonb not null check (pg_column_size(report) < 65536),
  created_at timestamptz not null default now()
);

create index if not exists battle_logs_recent on public.battle_logs (created_at desc);

alter table public.battle_logs enable row level security;

drop policy if exists "add own battles" on public.battle_logs;
create policy "add own battles" on public.battle_logs
  for insert to authenticated with check (auth.uid() = user_id);

-- The newest reports (legend fights only when p_legends), newest first, without account ids.
create or replace function public.recent_battles(p_limit int default 50, p_legends boolean default false)
returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json) from (
    select id, created_at, legend, outcome, players, report from battle_logs
    where not p_legends or legend <> ''
    order by created_at desc limit least(greatest(p_limit, 1), 500)) t;
$$;

revoke all on function public.recent_battles(int, boolean) from public;
grant execute on function public.recent_battles(int, boolean) to anon, authenticated;
