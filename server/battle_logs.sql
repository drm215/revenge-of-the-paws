-- Battle log for Revenge of the Paws: a report of every finished fight, for balancing.
-- Run once in the Supabase SQL editor (after supabase.sql). Safe to run again.
-- Signed-in players add their own reports. Reports hold no names, emails or account ids, and
-- recent_battles() hands them out without the account id, so balance checks can read them.
-- Limits: 120 reports an hour per player, the newest 500 per player, 180 days, 32 KB each.

create table if not exists public.battle_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  legend     text not null default '' check (char_length(legend) <= 40),
  outcome    text not null default '' check (char_length(outcome) <= 20),
  players    int not null default 1 check (players between 1 and 4),
  report     jsonb not null check (pg_column_size(report) < 32768),
  created_at timestamptz not null default now()
);

alter table public.battle_logs drop constraint if exists battle_logs_report_check;
alter table public.battle_logs add constraint battle_logs_report_check check (pg_column_size(report) < 32768) not valid;

create index if not exists battle_logs_recent on public.battle_logs (created_at desc);
create index if not exists battle_logs_by_player on public.battle_logs (user_id, id desc);

-- The server's clock decides when a report arrived, so the hourly limit can't be dodged. PT429
-- answers HTTP 429: the game keeps the report and tries again later.
create or replace function public.battle_logs_limits() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  if (select count(*) from battle_logs where user_id = new.user_id and created_at > now() - interval '1 hour') >= 120 then
    raise exception 'Too many battle reports. Try again later.' using errcode = 'PT429';
  end if;
  delete from battle_logs where created_at < now() - interval '180 days';
  delete from battle_logs where user_id = new.user_id and id in (
    select id from battle_logs where user_id = new.user_id order by id desc offset 499);
  return new;
end;
$$;

revoke all on function public.battle_logs_limits() from public, anon, authenticated;

drop trigger if exists battle_logs_limits on public.battle_logs;
create trigger battle_logs_limits before insert on public.battle_logs
  for each row execute function public.battle_logs_limits();

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
    order by created_at desc limit least(greatest(p_limit, 1), 200)) t;
$$;

revoke all on function public.recent_battles(int, boolean) from public;
grant execute on function public.recent_battles(int, boolean) to anon, authenticated;
