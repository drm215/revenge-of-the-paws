-- Cloud saves for Revenge of the Paws. Run once in the Supabase SQL editor.
-- One row per player: the text of their profile.cfg and campaign.cfg. Row-level security means a
-- signed-in player can only see and change their own row; the anon key alone can do nothing.

create table if not exists public.saves (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  profile    text not null,
  campaign   text not null default '',
  device     text not null default '',
  updated_at timestamptz not null default now()
);

-- The server decides updated_at, so devices with wrong clocks can't confuse sync.
create or replace function public.saves_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists saves_touch on public.saves;
create trigger saves_touch before insert or update on public.saves
  for each row execute function public.saves_touch();

alter table public.saves enable row level security;

drop policy if exists "read own save" on public.saves;
drop policy if exists "insert own save" on public.saves;
drop policy if exists "update own save" on public.saves;
drop policy if exists "delete own save" on public.saves;

create policy "read own save" on public.saves
  for select using (auth.uid() = user_id);
create policy "insert own save" on public.saves
  for insert with check (auth.uid() = user_id);
create policy "update own save" on public.saves
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own save" on public.saves
  for delete using (auth.uid() = user_id);
