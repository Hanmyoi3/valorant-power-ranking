-- Run this entire file in Supabase Dashboard > SQL Editor.
create table if not exists public.app_state (
  id integer primary key check (id = 1),
  data jsonb not null default '{"players":[],"teamNames":{"A":"팀 1","B":"팀 2"},"categoryOptions":["IGL","FLEX","타격대","척후대","감시자","전략가","오퍼레이터"]}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_state enable row level security;
alter table public.admin_users enable row level security;

-- Anyone can read the public leaderboard.
drop policy if exists "Public can read app state" on public.app_state;
create policy "Public can read app state" on public.app_state for select using (true);

-- Only a user explicitly listed in admin_users can change site data.
drop policy if exists "Admins can insert app state" on public.app_state;
create policy "Admins can insert app state" on public.app_state for insert with check (exists (select 1 from public.admin_users a where a.user_id = auth.uid()));
drop policy if exists "Admins can update app state" on public.app_state;
create policy "Admins can update app state" on public.app_state for update using (exists (select 1 from public.admin_users a where a.user_id = auth.uid())) with check (exists (select 1 from public.admin_users a where a.user_id = auth.uid()));

-- Explicit grants; RLS below still decides which rows/actions are allowed.
grant select on public.app_state to anon, authenticated;
grant insert, update on public.app_state to authenticated;
grant select on public.admin_users to authenticated;

-- A logged-in user can only check their own admin membership.
drop policy if exists "Users can read own admin membership" on public.admin_users;
create policy "Users can read own admin membership" on public.admin_users for select using (user_id = auth.uid());

insert into public.app_state (id, data) values (1, '{"players":[],"teamNames":{"A":"팀 1","B":"팀 2"},"categoryOptions":["IGL","FLEX","타격대","척후대","감시자","전략가","오퍼레이터"]}'::jsonb) on conflict (id) do nothing;

-- After creating your admin account under Authentication > Users, run this once:
-- insert into public.admin_users (user_id) select id from auth.users where email = 'YOUR_ADMIN_EMAIL' on conflict do nothing;
