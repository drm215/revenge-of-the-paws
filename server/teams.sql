-- Teams for Revenge of the Paws. Run in the Supabase SQL editor (after supabase.sql); safe to run
-- again, and it upgrades the first version (one team per account) to one team per saved game.
-- Up to 4 players share one campaign map built from all their homes; each keeps their own critters.
-- A player can be on several teams, one per saved game; every call names the team it's about.
-- The shared map is one text blob with a version number: a save only lands if nobody else saved
-- since (save_team_state returns -1 and the game replays its moves on the newer map). The tables
-- have no policies, so players can only reach them through the functions below.

create table if not exists public.teams (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  state      text not null default '',
  version    bigint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id   uuid not null references public.teams (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  name      text not null check (char_length(name) between 1 and 40),
  zip       text not null check (zip ~ '^[0-9]{5}$'),
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- The first version allowed one team per account.
alter table public.team_members drop constraint if exists team_members_user_id_key;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;

drop function if exists public.my_team();
drop function if exists public.leave_team();
drop function if exists public.save_team_state(text, bigint);

create or replace function public.is_team_member(p_team uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members where team_id = p_team and user_id = auth.uid());
$$;

-- One of your teams: {id, code, state, version, members: [{user_id, name, zip}] in join order}, or null.
create or replace function public.team_info(p_team uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', t.id, 'code', t.code, 'state', t.state, 'version', t.version,
    'members', (select json_agg(json_build_object('user_id', m.user_id, 'name', m.name, 'zip', m.zip)
                order by m.joined_at, m.user_id) from team_members m where m.team_id = t.id))
  from teams t
  where t.id = p_team and is_team_member(p_team);
$$;

-- Every team you're on (newest first): [{id, code, members}], to bring one back into a saved game.
create or replace function public.my_teams() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', t.id, 'code', t.code,
    'members', (select json_agg(json_build_object('user_id', m.user_id, 'name', m.name, 'zip', m.zip)
                order by m.joined_at, m.user_id) from team_members m where m.team_id = t.id))
    order by me.joined_at desc), '[]'::json)
  from team_members me join teams t on t.id = me.team_id
  where me.user_id = auth.uid();
$$;

create or replace function public.create_team(p_name text, p_zip text) returns json
language plpgsql security definer set search_path = public as $$
declare
  t_id uuid;
  t_code text;
begin
  if auth.uid() is null then raise exception 'Log in first.'; end if;
  loop
    t_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from teams where code = t_code);
  end loop;
  insert into teams (code) values (t_code) returning id into t_id;
  insert into team_members (team_id, user_id, name, zip) values (t_id, auth.uid(), p_name, p_zip);
  return team_info(t_id);
end;
$$;

-- Joins a team by its code (joining one you're already on just updates your name and home).
create or replace function public.join_team(p_code text, p_name text, p_zip text) returns json
language plpgsql security definer set search_path = public as $$
declare
  t_id uuid;
begin
  if auth.uid() is null then raise exception 'Log in first.'; end if;
  select id into t_id from teams where code = upper(trim(p_code));
  if t_id is null then raise exception 'No team has that code.'; end if;
  if not is_team_member(t_id) and (select count(*) from team_members where team_id = t_id) >= 4 then
    raise exception 'That team is full (4 players).';
  end if;
  insert into team_members (team_id, user_id, name, zip) values (t_id, auth.uid(), p_name, p_zip)
  on conflict (team_id, user_id) do update set name = excluded.name, zip = excluded.zip;
  return team_info(t_id);
end;
$$;

-- Leaves a team; the last one out deletes it.
create or replace function public.leave_team(p_team uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from team_members where team_id = p_team and user_id = auth.uid();
  if not exists (select 1 from team_members where team_id = p_team) then
    delete from teams where id = p_team;
  end if;
end;
$$;

-- Saves a team's shared map if it's still at p_version. Returns the new version, or -1 if a
-- teammate saved first (or you're not on that team).
create or replace function public.save_team_state(p_team uuid, p_state text, p_version bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v bigint;
begin
  update teams set state = p_state, version = version + 1
  where id = p_team and version = p_version and is_team_member(p_team)
  returning version into v;
  return coalesce(v, -1);
end;
$$;

revoke all on function public.is_team_member(uuid) from public, anon;
revoke all on function public.team_info(uuid) from public, anon;
revoke all on function public.my_teams() from public, anon;
revoke all on function public.create_team(text, text) from public, anon;
revoke all on function public.join_team(text, text, text) from public, anon;
revoke all on function public.leave_team(uuid) from public, anon;
revoke all on function public.save_team_state(uuid, text, bigint) from public, anon;
grant execute on function public.team_info(uuid) to authenticated;
grant execute on function public.my_teams() to authenticated;
grant execute on function public.create_team(text, text) to authenticated;
grant execute on function public.join_team(text, text, text) to authenticated;
grant execute on function public.leave_team(uuid) to authenticated;
grant execute on function public.save_team_state(uuid, text, bigint) to authenticated;
