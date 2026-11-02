-- 서버별 독립 내전 데이터/비밀번호 시스템
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.discord_servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  password_hash text not null,
  data jsonb not null default '{"players":[],"teamNames":{"A":"팀 1","B":"팀 2"},"categoryOptions":["IGL","FLEX","타격대","척후대","감시자","전략가","오퍼레이터"]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.discord_servers enable row level security;
drop policy if exists "Public can list discord servers" on public.discord_servers;
revoke all on public.discord_servers from anon, authenticated;
create or replace view public.discord_server_list as
  select id, name, created_at from public.discord_servers;
grant select on public.discord_server_list to anon, authenticated;

create or replace function public.create_discord_server(p_name text, p_password text)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare new_id uuid;
begin
  if not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception '사이트 관리자 권한이 필요합니다.';
  end if;
  if length(trim(p_name)) < 1 or length(p_name) > 60 then raise exception '서버 이름은 1~60자로 입력해 주세요.'; end if;
  if length(p_password) < 8 then raise exception '서버 비밀번호는 8자 이상이어야 합니다.'; end if;
  insert into public.discord_servers(name,password_hash) values(trim(p_name), extensions.crypt(p_password, extensions.gen_salt('bf'))) returning id into new_id;
  return new_id;
end; $$;

create or replace function public.verify_server_password(p_server_id uuid, p_password text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists(select 1 from public.discord_servers where id=p_server_id and password_hash=extensions.crypt(p_password,password_hash));
$$;

create or replace function public.save_server_state(p_server_id uuid, p_password text, p_data jsonb)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if not exists(select 1 from public.discord_servers where id=p_server_id and password_hash=extensions.crypt(p_password,password_hash)) then
    raise exception '해당 서버의 비밀번호가 올바르지 않습니다.';
  end if;
  update public.discord_servers set data=p_data, updated_at=now() where id=p_server_id;
  if not found then raise exception '서버를 찾을 수 없습니다.'; end if;
end; $$;

create or replace function public.change_server_password(p_server_id uuid, p_old_password text, p_new_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(p_new_password) < 8 then raise exception '새 비밀번호는 8자 이상이어야 합니다.'; end if;
  update public.discord_servers set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf')), updated_at=now()
  where id=p_server_id and password_hash=extensions.crypt(p_old_password,password_hash);
  if not found then raise exception '현재 서버 비밀번호가 올바르지 않습니다.'; end if;
end; $$;


-- Public visitors can read only the JSON data through this function.
-- Direct table access stays revoked so password_hash is never exposed.
create or replace function public.get_server_state(p_server_id uuid, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare result jsonb;
begin
  select data into result
  from public.discord_servers
  where id = p_server_id
    and password_hash = extensions.crypt(p_password, password_hash);
  if result is null then
    raise exception '서버 비밀번호가 올바르지 않습니다.';
  end if;
  return result;
end; $$;

drop function if exists public.get_server_state(uuid);
grant execute on function public.get_server_state(uuid,text) to anon, authenticated;

grant execute on function public.create_discord_server(text,text) to authenticated;
grant execute on function public.verify_server_password(uuid,text) to anon, authenticated;
grant execute on function public.save_server_state(uuid,text,jsonb) to anon, authenticated;
grant execute on function public.change_server_password(uuid,text,text) to anon, authenticated;
