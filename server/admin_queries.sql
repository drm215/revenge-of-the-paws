-- Queries for the Supabase dashboard (SQL editor). Read-only: nothing here changes data, and
-- nothing here needs running as a migration. Copy the one you need.


-- 1. Games that aren't backing up: players whose fights keep arriving but whose saved game in the
--    cloud is more than an hour older than their latest fight. (Battle logs carry the save slot
--    and how long it's gone without uploading; older logs don't, so those count by player.)
with fights as (
  select user_id,
         coalesce(report->>'slot', '') as slot,
         max(created_at) as last_fight,
         max((report->>'unsynced_minutes')::int) as worst_unsynced_minutes,
         (array_agg(report->>'sync_error' order by created_at desc))[1] as last_sync_error
  from public.battle_logs
  where created_at > now() - interval '7 days'
  group by 1, 2
)
select u.email, f.slot, f.last_fight, s.updated_at as cloud_saved,
       f.last_fight - coalesce(s.updated_at, '-infinity') as behind_by,
       f.worst_unsynced_minutes, f.last_sync_error
from fights f
join auth.users u on u.id = f.user_id
left join lateral (
  select max(updated_at) as updated_at from public.saves
  where user_id = f.user_id and (f.slot = '' or slot = f.slot)
) s on true
where s.updated_at is null or f.last_fight > s.updated_at + interval '1 hour'
order by behind_by desc;


-- 2. One player's sync trouble, newest first (put their email in).
select e.created_at, e.slot, e.kind, e.code, e.message, e.detail
from public.sync_events e join auth.users u on u.id = e.user_id
where u.email = 'someone@example.com'
order by e.id desc
limit 100;


-- 3. Sync trouble across everyone this week, by kind.
select kind, code, count(*) as reports, count(distinct user_id) as players, max(created_at) as latest
from public.sync_events
where created_at > now() - interval '7 days'
group by 1, 2
order by reports desc;


-- 4. One player's saved games in the cloud and the levels in each (put their email in).
select s.slot, s.updated_at, s.device,
       substring(s.profile from 'pet_name="([^"]*)"') as pet,
       substring(s.profile from 'team_id="([^"]*)"') as team_id
from public.saves s join auth.users u on u.id = s.user_id
where u.email = 'someone@example.com'
order by s.updated_at desc;


-- 5. Put back a deleted game. A deleted game's cloud copy is kept, renamed deleted_<time>_<slot>.
--    First list them (put their email in), then rename the one to restore back to its slot: the
--    player's device downloads it on the next sync.
select s.slot, s.updated_at, substring(s.profile from 'pet_name="([^"]*)"') as pet
from public.saves s join auth.users u on u.id = s.user_id
where u.email = 'someone@example.com' and s.slot like 'deleted\_%'
order by s.updated_at desc;
-- update public.saves set slot = regexp_replace(slot, '^deleted_[0-9]+_', '')
-- where user_id = (select id from auth.users where email = 'someone@example.com') and slot = 'deleted_..._save_...';
