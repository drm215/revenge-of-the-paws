-- Team chat for Revenge of the Paws. Run in the Supabase SQL editor (after teams.sql); safe to run
-- again. Every call names the team (a player can be on one team per saved game).
-- Quick-chat phrases, map pings and typed messages between teammates. Players reach the table only
-- through the functions below: they can post to and read their own team's chat, nothing else.
-- Messages are capped at 200 characters, 5 per 10 seconds per player, and the last 200 per team.

create table if not exists public.team_messages (
  id         bigint generated always as identity primary key,
  team_id    uuid not null references public.teams (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null,
  body       text not null check (char_length(body) between 1 and 200),
  ping       text not null default '',  -- territory (ZIP) id for a map ping
  created_at timestamptz not null default now()
);

create index if not exists team_messages_team on public.team_messages (team_id, id);

alter table public.team_messages enable row level security;

drop function if exists public.send_team_message(text, text);
drop function if exists public.team_messages_since(bigint);

-- Posts to your team's chat. Returns the new message id.
create or replace function public.send_team_message(p_team uuid, p_body text, p_ping text default '') returns bigint
language plpgsql security definer set search_path = public as $$
declare
  t_id uuid := p_team;
  who text;
  new_id bigint;
begin
  select name into who from team_members where team_id = p_team and user_id = auth.uid();
  if who is null then raise exception 'You are not on that team.'; end if;
  if char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'Type a message first.'; end if;
  if (select count(*) from team_messages
      where user_id = auth.uid() and created_at > now() - interval '10 seconds') >= 5 then
    raise exception 'Slow down: wait a few seconds between messages.';
  end if;
  insert into team_messages (team_id, user_id, name, body, ping)
  values (t_id, auth.uid(), who, left(trim(p_body), 200), coalesce(p_ping, ''))
  returning id into new_id;
  delete from team_messages where team_id = t_id and id < (
    select id from team_messages where team_id = t_id order by id desc offset 199 limit 1);
  return new_id;
end;
$$;

-- Your team's messages newer than p_after (up to 100), oldest first.
create or replace function public.team_messages_since(p_team uuid, p_after bigint) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(m order by m.id), '[]'::json) from (
    select id, user_id, name, body, ping, created_at from team_messages
    where team_id = p_team and is_team_member(p_team) and id > p_after
    order by id desc limit 100) m;
$$;

revoke all on function public.send_team_message(uuid, text, text) from public, anon;
revoke all on function public.team_messages_since(uuid, bigint) from public, anon;
grant execute on function public.send_team_message(uuid, text, text) to authenticated;
grant execute on function public.team_messages_since(uuid, bigint) to authenticated;
