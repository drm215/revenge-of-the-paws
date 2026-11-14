-- Version history for Revenge of the Paws: older copies of every saved game and every team's shared
-- map, which players can put back from the game. Run in the Supabase SQL editor after
-- supabase.sql, teams.sql and chat.sql; safe to run again.
--
-- When a copy is replaced, the old one is kept if the newest kept copy is 20 minutes old (so a
-- session of play leaves one copy every 20 minutes, not one per move), and always when the new copy
-- looks like lost progress (much shorter text, or 3+ fewer territories held) or when a restore
-- replaces it. Kept: the newest 30 copies, plus the last copy of each day for 30 days.
-- The tables have no policies: players reach them only through the functions below, and only
-- their own games and their own teams' maps.

create table if not exists public.save_history (
  id       bigint generated always as identity primary key,
  user_id  uuid not null references auth.users (id) on delete cascade,
  slot     text not null,
  profile  text not null,
  campaign text not null default '',
  device   text not null default '',
  saved_at timestamptz not null  -- when this copy became the cloud's (its updated_at)
);
create index if not exists save_history_game on public.save_history (user_id, slot, saved_at desc);

create table if not exists public.team_history (
  id       bigint generated always as identity primary key,
  team_id  uuid not null references public.teams (id) on delete cascade,
  version  bigint not null,
  state    text not null,
  saved_at timestamptz not null default now()  -- when this copy was replaced
);
create index if not exists team_history_team on public.team_history (team_id, saved_at desc);

alter table public.save_history enable row level security;
alter table public.team_history enable row level security;

-- The territories held in a save's campaign text (the owned=[...] line: two quotes per ZIP).
create or replace function public.paws_owned(c text) returns int
language sql immutable as $$
  select coalesce((length(x) - length(replace(x, '"', ''))) / 2, 0)
  from (select substring(coalesce(c, '') from '(?n)^owned=([^\n]*)') as x) s;
$$;

create or replace function public.paws_turn(c text) returns int
language sql immutable as $$
  select coalesce(substring(coalesce(c, '') from '(?n)^turn=([0-9]+)')::int, 0);
$$;

-- Whether replacing `old_text` with `new_text` should keep the old copy no matter how recent the
-- last kept one is.
create or replace function public.paws_looks_lost(old_text text, new_text text) returns boolean
language sql immutable as $$
  select length(coalesce(new_text, '')) < 0.8 * length(coalesce(old_text, ''))
      or paws_owned(new_text) <= paws_owned(old_text) - 3;
$$;

-- --- Saved games --------------------------------------------------------------------------------

create or replace function public.saves_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  last_kept timestamptz;
begin
  if old.profile is not distinct from new.profile and old.campaign is not distinct from new.campaign then
    return new;  -- a rename (into or out of the trash), nothing to keep
  end if;
  select max(saved_at) into last_kept from save_history where user_id = old.user_id and slot = old.slot;
  if current_setting('paws.snapshot', true) = 'force'
     or last_kept is null or last_kept < now() - interval '20 minutes'
     or paws_looks_lost(old.campaign, new.campaign) or paws_looks_lost(old.profile, new.profile) then
    insert into save_history (user_id, slot, profile, campaign, device, saved_at)
    values (old.user_id, old.slot, old.profile, old.campaign, old.device, old.updated_at);
    delete from save_history where id in (
      select id from (
        select id, saved_at,
               row_number() over (order by saved_at desc, id desc) as n,
               row_number() over (partition by date_trunc('day', saved_at) order by saved_at desc, id desc) as d
        from save_history where user_id = old.user_id and slot = old.slot) h
      where n > 30 and not (d = 1 and saved_at > now() - interval '30 days'));
  end if;
  return new;
end;
$$;

drop trigger if exists saves_keep_history on public.saves;
create trigger saves_keep_history before update on public.saves
  for each row execute function public.saves_keep_history();

-- Older copies of one of your saved games, newest first: [{id, saved_at, profile, owned, turn}].
create or replace function public.save_versions(p_slot text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', h.id, 'saved_at', h.saved_at, 'profile', h.profile,
    'owned', paws_owned(h.campaign), 'turn', paws_turn(h.campaign)) order by h.saved_at desc, h.id desc), '[]'::json)
  from save_history h
  where h.user_id = auth.uid() and h.slot = p_slot;
$$;

-- Makes an older copy the game's cloud copy again (the copy it replaces is kept). Returns the new
-- cloud row {slot, profile, campaign, updated_at}.
create or replace function public.restore_save(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  h save_history;
  r saves;
begin
  select * into h from save_history where id = p_id and user_id = auth.uid();
  if not found then raise exception 'That copy is gone.'; end if;
  perform set_config('paws.snapshot', 'force', true);
  update saves set profile = h.profile, campaign = h.campaign, device = 'restored'
    where user_id = auth.uid() and slot = h.slot returning * into r;
  if not found then
    insert into saves (user_id, slot, profile, campaign, device)
    values (auth.uid(), h.slot, h.profile, h.campaign, 'restored') returning * into r;
  end if;
  perform set_config('paws.snapshot', '', true);
  return json_build_object('slot', r.slot, 'profile', r.profile, 'campaign', r.campaign, 'updated_at', r.updated_at);
end;
$$;

-- --- Team maps ----------------------------------------------------------------------------------

create or replace function public.teams_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  last_kept timestamptz;
begin
  if old.state is not distinct from new.state or old.state = '' then
    return new;
  end if;
  select max(saved_at) into last_kept from team_history where team_id = old.id;
  if current_setting('paws.snapshot', true) = 'force'
     or last_kept is null or last_kept < now() - interval '20 minutes'
     or paws_looks_lost(old.state, new.state) then
    insert into team_history (team_id, version, state) values (old.id, old.version, old.state);
    delete from team_history where id in (
      select id from (
        select id, saved_at,
               row_number() over (order by saved_at desc, id desc) as n,
               row_number() over (partition by date_trunc('day', saved_at) order by saved_at desc, id desc) as d
        from team_history where team_id = old.id) h
      where n > 30 and not (d = 1 and saved_at > now() - interval '30 days'));
  end if;
  return new;
end;
$$;

drop trigger if exists teams_keep_history on public.teams;
create trigger teams_keep_history before update on public.teams
  for each row execute function public.teams_keep_history();

-- Older copies of one of your teams' shared maps, newest first: [{id, saved_at, version, owned, turn}].
create or replace function public.team_versions(p_team uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', h.id, 'saved_at', h.saved_at, 'version', h.version,
    'owned', paws_owned(h.state), 'turn', paws_turn(h.state)) order by h.saved_at desc, h.id desc), '[]'::json)
  from team_history h
  where h.team_id = p_team and is_team_member(p_team);
$$;

-- Puts a team's shared map back to an older copy, for everyone (the map it replaces is kept), and
-- says so in the team chat. Returns team_info().
create or replace function public.restore_team_state(p_team uuid, p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  h team_history;
  who text;
begin
  select name into who from team_members where team_id = p_team and user_id = auth.uid();
  if who is null then raise exception 'You are not on that team.'; end if;
  select * into h from team_history where id = p_id and team_id = p_team;
  if not found then raise exception 'That copy is gone.'; end if;
  perform set_config('paws.snapshot', 'force', true);
  update teams set state = h.state, version = version + 1 where id = p_team;
  perform set_config('paws.snapshot', '', true);
  insert into team_messages (team_id, user_id, name, body)
  values (p_team, auth.uid(), who, format('Put the team map back to an earlier copy: turn %s, %s %s held.',
    paws_turn(h.state), paws_owned(h.state), case when paws_owned(h.state) = 1 then 'territory' else 'territories' end));
  return team_info(p_team);
end;
$$;

revoke all on function public.save_versions(text) from public, anon;
revoke all on function public.restore_save(bigint) from public, anon;
revoke all on function public.team_versions(uuid) from public, anon;
revoke all on function public.restore_team_state(uuid, bigint) from public, anon;
grant execute on function public.save_versions(text) to authenticated;
grant execute on function public.restore_save(bigint) to authenticated;
grant execute on function public.team_versions(uuid) to authenticated;
grant execute on function public.restore_team_state(uuid, bigint) to authenticated;
