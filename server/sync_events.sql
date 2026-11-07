-- Sync trouble reports for Revenge of the Paws: what went wrong when a device couldn't back up a
-- saved game (a failed upload or read, a lost login, a conflict, a cloud copy replacing newer
-- progress), so a lost game can be traced. Run once in the Supabase SQL editor (after
-- supabase.sql). Safe to run again.
-- Signed-in players add their own; nobody can read them through the API (the dashboard can).
-- Limits: 60 an hour per player, the newest 300 per player, 90 days, 8 KB each.

create table if not exists public.sync_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  slot       text not null default '' check (char_length(slot) <= 60),
  kind       text not null check (char_length(kind) between 1 and 40),
  code       int not null default 0,
  message    text not null default '' check (char_length(message) <= 300),
  detail     jsonb not null default '{}' check (pg_column_size(detail) < 8192),
  created_at timestamptz not null default now()
);

create index if not exists sync_events_by_player on public.sync_events (user_id, id desc);

create or replace function public.sync_events_limits() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  if (select count(*) from sync_events where user_id = new.user_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Too many sync reports. Try again later.' using errcode = 'PT429';
  end if;
  delete from sync_events where created_at < now() - interval '90 days';
  delete from sync_events where user_id = new.user_id and id in (
    select id from sync_events where user_id = new.user_id order by id desc offset 299);
  return new;
end;
$$;

revoke all on function public.sync_events_limits() from public, anon, authenticated;

drop trigger if exists sync_events_limits on public.sync_events;
create trigger sync_events_limits before insert on public.sync_events
  for each row execute function public.sync_events_limits();

alter table public.sync_events enable row level security;

drop policy if exists "add own sync events" on public.sync_events;
create policy "add own sync events" on public.sync_events
  for insert to authenticated with check (auth.uid() = user_id);
