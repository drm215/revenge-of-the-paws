-- Legend raids for Revenge of the Paws. Run once in the Supabase SQL editor (after teams.sql).
-- Up to 4 teammates fight a legend together, live, each controlling the 3 critters they bring.
-- Every device runs the same battle from the same seed and config; only the players' moves are
-- shared, numbered in order (the first move posted for a number wins, so a timeout takeover can't
-- clash with a late reply). Players reach the tables only through the functions below.

create table if not exists public.raids (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  host       uuid not null references auth.users (id) on delete cascade,
  territory  text not null,
  legend     text not null,
  seed       bigint not null,
  config     text not null default '',  -- the battle (waves, zombie strength...), fixed at the start
  status     text not null default 'lobby' check (status in ('lobby', 'fighting', 'done', 'cancelled')),
  result     text not null default '',  -- who won, the XP each player gets, who was knocked out
  created_at timestamptz not null default now()
);

create table if not exists public.raid_members (
  raid_id   uuid not null references public.raids (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  name      text not null,
  pack      text not null default '',  -- the 3 critters they bring (Profile.snapshot)
  ready     boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (raid_id, user_id)
);

create table if not exists public.raid_actions (
  raid_id uuid not null references public.raids (id) on delete cascade,
  seq     int not null,
  user_id uuid not null,
  action  text not null,
  primary key (raid_id, seq)
);

alter table public.raids enable row level security;
alter table public.raid_members enable row level security;
alter table public.raid_actions enable row level security;

create or replace function public.raid_my_team() returns uuid
language sql stable security definer set search_path = public as $$
  select team_id from team_members where user_id = auth.uid();
$$;

-- The team's latest raid (open, fighting, or finished in the last day), with its members; or null.
create or replace function public.team_raid() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', r.id, 'host', r.host, 'territory', r.territory, 'legend', r.legend, 'seed', r.seed,
    'config', r.config, 'status', r.status, 'result', r.result, 'created_at', r.created_at,
    'members', (select coalesce(json_agg(json_build_object('user_id', m.user_id, 'name', m.name,
                'pack', m.pack, 'ready', m.ready) order by m.joined_at, m.user_id), '[]'::json)
                from raid_members m where m.raid_id = r.id))
  from raids r
  where r.team_id = raid_my_team() and r.status <> 'cancelled' and r.created_at > now() - interval '1 day'
  order by r.created_at desc limit 1;
$$;

-- Opens a raid lobby on a legend's lair; the opener is in it, ready, with their pack.
create or replace function public.open_raid(p_territory text, p_legend text, p_seed bigint, p_name text, p_pack text) returns json
language plpgsql security definer set search_path = public as $$
declare
  t_id uuid := raid_my_team();
  r_id uuid;
begin
  if t_id is null then raise exception 'Join a team first.'; end if;
  update raids set status = 'cancelled'
  where team_id = t_id and status in ('lobby', 'fighting') and created_at < now() - interval '2 hours';
  if exists (select 1 from raids where team_id = t_id and status in ('lobby', 'fighting')) then
    raise exception 'Your team already has a raid going. Join it from the map.';
  end if;
  insert into raids (team_id, host, territory, legend, seed) values (t_id, auth.uid(), p_territory, p_legend, p_seed)
  returning id into r_id;
  insert into raid_members (raid_id, user_id, name, pack, ready) values (r_id, auth.uid(), p_name, p_pack, true);
  return team_raid();
end;
$$;

-- Joins the open lobby (or updates your pack and ready state).
create or replace function public.join_raid(p_name text, p_pack text, p_ready boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
  r_id uuid;
begin
  select id into r_id from raids where team_id = raid_my_team() and status = 'lobby' order by created_at desc limit 1;
  if r_id is null then raise exception 'There is no raid to join right now.'; end if;
  if not exists (select 1 from raid_members where raid_id = r_id and user_id = auth.uid())
     and (select count(*) from raid_members where raid_id = r_id) >= 4 then
    raise exception 'The raid is full (4 players).';
  end if;
  insert into raid_members (raid_id, user_id, name, pack, ready) values (r_id, auth.uid(), p_name, p_pack, p_ready)
  on conflict (raid_id, user_id) do update set name = excluded.name, pack = excluded.pack, ready = excluded.ready;
  return team_raid();
end;
$$;

-- Leaves the lobby; if the opener leaves, the raid is called off.
create or replace function public.leave_raid() returns void
language plpgsql security definer set search_path = public as $$
declare
  r raids;
begin
  select * into r from raids where team_id = raid_my_team() and status = 'lobby' order by created_at desc limit 1;
  if r.id is null then return; end if;
  if r.host = auth.uid() then
    update raids set status = 'cancelled' where id = r.id;
  else
    delete from raid_members where raid_id = r.id and user_id = auth.uid();
  end if;
end;
$$;

-- The opener starts the fight with everyone who is ready, fixing the battle config.
create or replace function public.start_raid(p_config text) returns json
language plpgsql security definer set search_path = public as $$
declare
  r raids;
begin
  select * into r from raids where team_id = raid_my_team() and status = 'lobby' order by created_at desc limit 1;
  if r.id is null then raise exception 'There is no raid to start.'; end if;
  if r.host <> auth.uid() then raise exception 'Only the player who opened the raid can start it.'; end if;
  delete from raid_members where raid_id = r.id and not ready;
  update raids set status = 'fighting', config = p_config where id = r.id;
  return team_raid();
end;
$$;

-- Posts the move numbered p_seq. The first move posted for a number stands: returns the stored one.
create or replace function public.post_raid_action(p_raid uuid, p_seq int, p_action text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from raid_members where raid_id = p_raid and user_id = auth.uid()) then
    raise exception 'You are not in this raid.';
  end if;
  insert into raid_actions (raid_id, seq, user_id, action) values (p_raid, p_seq, auth.uid(), p_action)
  on conflict (raid_id, seq) do nothing;
  return (select json_build_object('seq', seq, 'user_id', user_id, 'action', action)
          from raid_actions where raid_id = p_raid and seq = p_seq);
end;
$$;

-- Moves numbered after p_after, in order.
create or replace function public.raid_actions_after(p_raid uuid, p_after int) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('seq', a.seq, 'user_id', a.user_id, 'action', a.action) order by a.seq), '[]'::json)
  from raid_actions a
  where a.raid_id = p_raid and a.seq > p_after
    and exists (select 1 from raid_members where raid_id = p_raid and user_id = auth.uid());
$$;

-- Records how the fight ended; the first result posted stands. Returns {result, mine}.
create or replace function public.finish_raid(p_raid uuid, p_result text) returns json
language plpgsql security definer set search_path = public as $$
declare
  changed int;
begin
  if not exists (select 1 from raid_members where raid_id = p_raid and user_id = auth.uid()) then
    raise exception 'You are not in this raid.';
  end if;
  update raids set status = 'done', result = p_result where id = p_raid and status = 'fighting';
  get diagnostics changed = row_count;
  return json_build_object('result', (select result from raids where id = p_raid), 'mine', changed > 0);
end;
$$;

revoke all on function public.raid_my_team() from public;
revoke all on function public.team_raid() from public;
revoke all on function public.open_raid(text, text, bigint, text, text) from public;
revoke all on function public.join_raid(text, text, boolean) from public;
revoke all on function public.leave_raid() from public;
revoke all on function public.start_raid(text) from public;
revoke all on function public.post_raid_action(uuid, int, text) from public;
revoke all on function public.raid_actions_after(uuid, int) from public;
revoke all on function public.finish_raid(uuid, text) from public;
grant execute on function public.team_raid() to authenticated;
grant execute on function public.open_raid(text, text, bigint, text, text) to authenticated;
grant execute on function public.join_raid(text, text, boolean) to authenticated;
grant execute on function public.leave_raid() to authenticated;
grant execute on function public.start_raid(text) to authenticated;
grant execute on function public.post_raid_action(uuid, int, text) to authenticated;
grant execute on function public.raid_actions_after(uuid, int) to authenticated;
grant execute on function public.finish_raid(uuid, text) to authenticated;
