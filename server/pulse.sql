-- One check-in for everything a team's game watches, for Revenge of the Paws. Run in the Supabase SQL
-- editor after teams.sql, chat.sql and raids.sql; safe to run again.
-- The game sends the tags it got last time, and the team's map and raid only come back if they
-- changed, so a quiet game costs one small request instead of three large ones.

create or replace function public.team_pulse(p_team uuid, p_team_tag text, p_raid_tag text, p_after bigint) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  t json;
  r json;
  t_tag text;
  r_tag text;
begin
  if not is_team_member(p_team) then
    return null;
  end if;
  t := team_info(p_team);
  r := team_raid(p_team);
  t_tag := md5(t::text);
  r_tag := coalesce(md5(r::text), '');
  return json_build_object(
    'team_tag', t_tag,
    'team', case when t_tag is distinct from p_team_tag then t end,
    'raid_tag', r_tag,
    'raid_changed', r_tag is distinct from p_raid_tag,
    'raid', case when r_tag is distinct from p_raid_tag then r end,
    'messages', team_messages_since(p_team, p_after));
end;
$$;

revoke all on function public.team_pulse(uuid, text, text, bigint) from public, anon;
grant execute on function public.team_pulse(uuid, text, text, bigint) to authenticated;
