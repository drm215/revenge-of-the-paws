-- Critter transfers between teammates for Revenge of the Paws. Run in the Supabase SQL editor after
-- teams.sql, then run pulse.sql again (the check-in carries them); safe to run again.
--
-- A player offers one of their critters to a teammate, as a gift (for good) or a loan. Either way
-- the teammate accepts or declines. A loan can be ended any time: the owner calls it back, or the
-- borrower sends it back. The row carries the critter's state (Profile.critter_data(), JSON); while
-- on loan the borrower's game keeps it up to date, so the owner sees its level and gets back the
-- XP it earned. Each game applies the outcome to its own save (Transfers.reconcile): the server
-- only records who agreed to what. The table has no policies: players reach it only through the
-- functions below, and only rows they're part of.
--
-- status: offered -> declined (by the receiver) | cancelled (by the sender) | active (a loan,
-- accepted) | done (a gift, accepted); active -> recalled (by either side).

create table if not exists public.critter_transfers (
  id         bigint generated always as identity primary key,
  team_id    uuid not null references public.teams (id) on delete cascade,
  from_user  uuid not null references auth.users (id) on delete cascade,
  to_user    uuid not null references auth.users (id) on delete cascade,
  from_name  text not null,
  to_name    text not null,
  kind       text not null check (kind in ('gift', 'loan')),
  critter    text not null check (critter ~ '^[a-z_]{1,40}$'),
  data       text not null check (char_length(data) <= 20000),
  status     text not null default 'offered'
             check (status in ('offered', 'declined', 'cancelled', 'active', 'recalled', 'done')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists critter_transfers_team on public.critter_transfers (team_id, id);
alter table public.critter_transfers enable row level security;

-- One row as the game sees it.
create or replace function public.transfer_json(t critter_transfers) returns json
language sql stable as $$
  select json_build_object('id', t.id, 'from_user', t.from_user, 'to_user', t.to_user,
    'from_name', t.from_name, 'to_name', t.to_name, 'kind', t.kind, 'critter', t.critter,
    'data', t.data, 'status', t.status, 'updated_at', t.updated_at);
$$;

-- Your transfers on a team, oldest first: every open one, and the ones that ended in the last 30
-- days (a game that was away still has to see how they ended).
create or replace function public.my_transfers(p_team uuid) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(transfer_json(t) order by t.id), '[]'::json)
  from critter_transfers t
  where t.team_id = p_team and auth.uid() in (t.from_user, t.to_user)
    and (t.status in ('offered', 'active') or t.updated_at > now() - interval '30 days');
$$;

-- Offers critter p_critter to teammate p_to, as a 'gift' or a 'loan'. Returns the new row.
create or replace function public.offer_critter(p_team uuid, p_to uuid, p_kind text, p_critter text, p_data text) returns json
language plpgsql security definer set search_path = public as $$
declare
  me text;
  them text;
  t critter_transfers;
begin
  select name into me from team_members where team_id = p_team and user_id = auth.uid();
  if me is null then raise exception 'You are not on that team.'; end if;
  select name into them from team_members where team_id = p_team and user_id = p_to;
  if them is null or p_to = auth.uid() then raise exception 'That player is not on your team.'; end if;
  if p_kind not in ('gift', 'loan') then raise exception 'Give or lend?'; end if;
  if exists (select 1 from critter_transfers where team_id = p_team and from_user = auth.uid()
             and critter = p_critter and status in ('offered', 'active')) then
    raise exception 'That critter is already offered or on loan.';
  end if;
  if (select count(*) from critter_transfers where team_id = p_team and from_user = auth.uid() and status = 'offered') >= 6 then
    raise exception 'Too many offers waiting: wait for answers first.';
  end if;
  insert into critter_transfers (team_id, from_user, to_user, from_name, to_name, kind, critter, data)
  values (p_team, auth.uid(), p_to, me, them, p_kind, p_critter, p_data) returning * into t;
  return transfer_json(t);
end;
$$;

-- The receiver accepts (a gift is done, a loan is active) or declines an offer. Returns the row.
create or replace function public.answer_transfer(p_id bigint, p_accept boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
  t critter_transfers;
begin
  update critter_transfers
  set status = case when not p_accept then 'declined' when kind = 'gift' then 'done' else 'active' end,
      updated_at = now()
  where id = p_id and to_user = auth.uid() and status = 'offered'
  returning * into t;
  if not found then raise exception 'That offer is no longer open.'; end if;
  return transfer_json(t);
end;
$$;

-- The sender takes back an offer nobody has answered yet. Returns the row.
create or replace function public.cancel_transfer(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  t critter_transfers;
begin
  update critter_transfers set status = 'cancelled', updated_at = now()
  where id = p_id and from_user = auth.uid() and status = 'offered'
  returning * into t;
  if not found then raise exception 'That offer is no longer open.'; end if;
  return transfer_json(t);
end;
$$;

-- Ends a loan: the owner calls it back, or the borrower sends it back (even after leaving the
-- team). Returns the row.
create or replace function public.end_loan(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
  t critter_transfers;
begin
  update critter_transfers set status = 'recalled', updated_at = now()
  where id = p_id and auth.uid() in (from_user, to_user) and status = 'active'
  returning * into t;
  if not found then raise exception 'That loan is already over.'; end if;
  return transfer_json(t);
end;
$$;

-- The borrower's game reports how the loaned critter is doing (its level grows on loan). False if
-- the loan is over.
create or replace function public.update_loan(p_id bigint, p_data text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update critter_transfers set data = p_data, updated_at = now()
  where id = p_id and to_user = auth.uid() and status = 'active' and char_length(p_data) <= 20000;
  return found;
end;
$$;

revoke all on function public.transfer_json(critter_transfers) from public, anon;
revoke all on function public.my_transfers(uuid) from public, anon;
revoke all on function public.offer_critter(uuid, uuid, text, text, text) from public, anon;
revoke all on function public.answer_transfer(bigint, boolean) from public, anon;
revoke all on function public.cancel_transfer(bigint) from public, anon;
revoke all on function public.end_loan(bigint) from public, anon;
revoke all on function public.update_loan(bigint, text) from public, anon;
grant execute on function public.my_transfers(uuid) to authenticated;
grant execute on function public.offer_critter(uuid, uuid, text, text, text) to authenticated;
grant execute on function public.answer_transfer(bigint, boolean) to authenticated;
grant execute on function public.cancel_transfer(bigint) to authenticated;
grant execute on function public.end_loan(bigint) to authenticated;
grant execute on function public.update_loan(bigint, text) to authenticated;
