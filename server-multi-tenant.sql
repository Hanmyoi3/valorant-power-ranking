-- PB팀메이커 v8 멀티테넌트 / Google 계정 / 서버 회원 관리
drop function if exists public.get_server_state(uuid);
drop function if exists public.create_discord_server(text,text);
-- Supabase Dashboard > SQL Editor에서 기존 서버 스키마에 대해 실행하세요.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null unique check (char_length(nickname) between 2 and 20),
  created_at timestamptz not null default now()
);

create table if not exists public.discord_servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  owner_id uuid references auth.users(id) on delete set null,
  password_hash text not null,
  is_public boolean not null default true,
  view_password_hash text,
  profile_image_url text,
  data jsonb not null default '{"players":[],"teamNames":{"A":"팀 1","B":"팀 2"},"categoryOptions":["IGL","FLEX","타격대","척후대","감시자","전략가","오퍼레이터"]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.discord_servers add column if not exists owner_id uuid references auth.users(id) on delete set null;
alter table public.discord_servers add column if not exists is_public boolean not null default true;
alter table public.discord_servers add column if not exists view_password_hash text;
alter table public.discord_servers add column if not exists profile_image_url text;

create table if not exists public.server_creation_claims (
  user_id uuid primary key references auth.users(id) on delete cascade,
  server_id uuid unique,
  created_at timestamptz not null default now()
);

create table if not exists public.server_members (
  server_id uuid not null references public.discord_servers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member','admin','owner')),
  joined_at timestamptz not null default now(),
  primary key(server_id,user_id)
);

alter table public.user_profiles enable row level security;
alter table public.discord_servers enable row level security;
alter table public.server_members enable row level security;
revoke all on public.discord_servers from anon, authenticated;
revoke all on public.server_members from anon, authenticated;
revoke all on public.user_profiles from anon, authenticated;

drop policy if exists "read own profile" on public.user_profiles;
create policy "read own profile" on public.user_profiles for select to authenticated using(user_id=auth.uid());
drop policy if exists "read own memberships" on public.server_members;
create policy "read own memberships" on public.server_members for select to authenticated using(user_id=auth.uid());
grant select on public.user_profiles, public.server_members to authenticated;

-- Public server directory exposes metadata only, never password hashes or private roster data.
drop view if exists public.discord_server_list;
create view public.discord_server_list with (security_barrier=true) as
 select s.id,s.name,s.owner_id,s.is_public,s.profile_image_url,s.created_at,
        (select count(*)::int from public.server_members m where m.server_id=s.id) as member_count
 from public.discord_servers s;
grant select on public.discord_server_list to anon, authenticated;

create or replace function public.set_my_nickname(p_nickname text)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then raise exception 'Google 로그인 후 이용해 주세요.'; end if;
 if char_length(trim(p_nickname)) not between 2 and 20 then raise exception '닉네임은 2~20자로 입력해 주세요.'; end if;
 insert into public.user_profiles(user_id,nickname) values(auth.uid(),trim(p_nickname))
 on conflict(user_id) do update set nickname=excluded.nickname;
end; $$;

create or replace function public.create_discord_server(p_name text,p_password text,p_is_public boolean default true,p_view_password text default '')
returns uuid language plpgsql security definer set search_path=public,extensions,auth as $$
declare new_id uuid;
begin
 if auth.uid() is null then raise exception 'Google 로그인 후 서버를 생성할 수 있습니다.'; end if;
 if not exists(select 1 from public.user_profiles where user_id=auth.uid()) then raise exception '먼저 닉네임을 설정해 주세요.'; end if;
 if exists(select 1 from public.server_creation_claims where user_id=auth.uid()) then raise exception '계정당 서버는 평생 1개만 생성할 수 있습니다.'; end if;
 if char_length(trim(p_name)) not between 1 and 60 then raise exception '서버 이름은 1~60자로 입력해 주세요.'; end if;
 if length(p_password)<8 then raise exception '서버 관리자 비밀번호는 8자 이상이어야 합니다.'; end if;
 if not p_is_public and length(coalesce(p_view_password,''))<8 then raise exception '비공개 서버 열람 비밀번호는 8자 이상이어야 합니다.'; end if;
 insert into public.discord_servers(name,owner_id,password_hash,is_public,view_password_hash)
 values(trim(p_name),auth.uid(),extensions.crypt(p_password,extensions.gen_salt('bf')),p_is_public,
        case when p_is_public then null else extensions.crypt(p_view_password,extensions.gen_salt('bf')) end)
 returning id into new_id;
 insert into public.server_creation_claims(user_id,server_id) values(auth.uid(),new_id);
 insert into public.server_members(server_id,user_id,role) values(new_id,auth.uid(),'owner');
 return new_id;
end; $$;

create or replace function public.get_server_state(p_server_id uuid,p_view_password text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions,auth as $$
declare result jsonb; is_open boolean; vhash text;
begin
 select data,is_public,view_password_hash into result,is_open,vhash from public.discord_servers where id=p_server_id;
 if result is null then raise exception '서버를 찾을 수 없습니다.'; end if;
 if not is_open and not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid())
   and (vhash is null or vhash<>extensions.crypt(coalesce(p_view_password,''),vhash)) then
   raise exception '비공개 서버입니다. 올바른 열람 비밀번호가 필요합니다.';
 end if;
 return result;
end; $$;

create or replace function public.join_discord_server(p_server_id uuid,p_view_password text default '')
returns void language plpgsql security definer set search_path=public,extensions,auth as $$
declare is_open boolean; vhash text;
begin
 if auth.uid() is null then raise exception 'Google 로그인 후 이용해 주세요.'; end if;
 select is_public,view_password_hash into is_open,vhash from public.discord_servers where id=p_server_id;
 if not found then raise exception '서버를 찾을 수 없습니다.'; end if;
 if not is_open and (vhash is null or vhash<>extensions.crypt(coalesce(p_view_password,''),vhash)) then raise exception '열람 비밀번호가 올바르지 않습니다.'; end if;
 insert into public.server_members(server_id,user_id,role) values(p_server_id,auth.uid(),'member') on conflict do nothing;
end; $$;

create or replace function public.update_discord_server_profile(p_server_id uuid,p_name text,p_image_url text,p_is_public boolean,p_view_password text default '')
returns void language plpgsql security definer set search_path=public,extensions,auth as $$
begin
 if not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role in ('owner','admin'))
   and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '서버 관리자만 설정할 수 있습니다.'; end if;
 if char_length(trim(p_name)) not between 1 and 60 then raise exception '서버 이름은 1~60자로 입력해 주세요.'; end if;
 if not p_is_public and length(coalesce(p_view_password,''))<8 and not exists(select 1 from public.discord_servers where id=p_server_id and view_password_hash is not null) then
   raise exception '열람 비밀번호는 8자 이상이어야 합니다.';
 end if;
 update public.discord_servers set name=trim(p_name),profile_image_url=nullif(trim(p_image_url),''),is_public=p_is_public,
   view_password_hash=case when p_is_public then null when length(coalesce(p_view_password,''))>=8 then extensions.crypt(p_view_password,extensions.gen_salt('bf')) else view_password_hash end,
   updated_at=now() where id=p_server_id;
end; $$;

create or replace function public.list_server_members(p_server_id uuid)
returns table(user_id uuid,nickname text,email text,role text,joined_at timestamptz)
language plpgsql security definer set search_path=public,auth as $$
begin
 if not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role in ('owner','admin'))
 and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '서버 관리자만 참여자 목록을 볼 수 있습니다.'; end if;
 return query select m.user_id,coalesce(p.nickname,''),u.email::text,m.role,m.joined_at from public.server_members m
 left join public.user_profiles p on p.user_id=m.user_id left join auth.users u on u.id=m.user_id
 where m.server_id=p_server_id order by m.joined_at;
end; $$;

create or replace function public.kick_server_member(p_server_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role in ('owner','admin'))
 and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '서버 관리자만 강퇴할 수 있습니다.'; end if;
 delete from public.server_members where server_id=p_server_id and user_id=p_user_id and role<>'owner';
end; $$;

create or replace function public.promote_server_member(p_server_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role='owner')
 and not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '서버 소유자만 부관리자를 지정할 수 있습니다.'; end if;
 update public.server_members set role='admin' where server_id=p_server_id and user_id=p_user_id and role='member';
 if not found then raise exception '일반 참여자를 찾을 수 없습니다.'; end if;
end; $$;

create or replace function public.save_server_state(p_server_id uuid,p_password text,p_data jsonb)
returns void language plpgsql security definer set search_path=public,extensions,auth as $$
begin
 if not exists(select 1 from public.admin_users where user_id=auth.uid())
 and not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role in ('owner','admin'))
 and not exists(select 1 from public.discord_servers where id=p_server_id and password_hash=extensions.crypt(coalesce(p_password,''),password_hash)) then
   raise exception '서버 수정 권한이 없습니다.';
 end if;
 update public.discord_servers set data=p_data,updated_at=now() where id=p_server_id;
 if not found then raise exception '서버를 찾을 수 없습니다.'; end if;
end; $$;

create or replace function public.verify_server_password(p_server_id uuid,p_password text)
returns boolean language plpgsql security definer set search_path=public,extensions,auth as $$
declare ok boolean;
begin
 select exists(select 1 from public.discord_servers where id=p_server_id and password_hash=extensions.crypt(p_password,password_hash)) into ok;
 if ok and auth.uid() is not null then
   insert into public.server_members(server_id,user_id,role) values(p_server_id,auth.uid(),'admin')
   on conflict(server_id,user_id) do update set role=case when public.server_members.role='owner' then 'owner' else 'admin' end;
 end if;
 return coalesce(ok,false);
end; $$;

create or replace function public.change_server_password(p_server_id uuid,p_old_password text,p_new_password text)
returns void language plpgsql security definer set search_path=public,extensions,auth as $$
begin
 if length(p_new_password)<8 then raise exception '새 비밀번호는 8자 이상이어야 합니다.'; end if;
 if not exists(select 1 from public.server_members where server_id=p_server_id and user_id=auth.uid() and role in ('owner','admin')) then raise exception '서버 관리자만 변경할 수 있습니다.'; end if;
 update public.discord_servers set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf')),updated_at=now()
 where id=p_server_id and password_hash=extensions.crypt(p_old_password,password_hash);
 if not found then raise exception '현재 서버 관리자 비밀번호가 올바르지 않습니다.'; end if;
end; $$;

create or replace function public.rename_discord_server(p_server_id uuid,p_name text)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '전체 관리자 권한이 필요합니다.'; end if;
 update public.discord_servers set name=trim(p_name),updated_at=now() where id=p_server_id;
end; $$;
create or replace function public.delete_discord_server(p_server_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not exists(select 1 from public.admin_users where user_id=auth.uid()) then raise exception '전체 관리자 권한이 필요합니다.'; end if;
 delete from public.discord_servers where id=p_server_id;
end; $$;

grant execute on function public.set_my_nickname(text) to authenticated;
grant execute on function public.create_discord_server(text,text,boolean,text) to authenticated;
grant execute on function public.get_server_state(uuid,text) to anon,authenticated;
grant execute on function public.join_discord_server(uuid,text) to authenticated;
grant execute on function public.update_discord_server_profile(uuid,text,text,boolean,text) to authenticated;
grant execute on function public.list_server_members(uuid) to authenticated;
grant execute on function public.kick_server_member(uuid,uuid) to authenticated;
grant execute on function public.promote_server_member(uuid,uuid) to authenticated;
grant execute on function public.save_server_state(uuid,text,jsonb) to authenticated;
grant execute on function public.verify_server_password(uuid,text) to anon,authenticated;
grant execute on function public.change_server_password(uuid,text,text) to authenticated;
grant execute on function public.rename_discord_server(uuid,text) to authenticated;
grant execute on function public.delete_discord_server(uuid) to authenticated;
