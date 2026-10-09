-- BOOKCHAT initial schema and RLS.
-- Applied to Supabase project xgrbndqcftcyrqpmzmys.
create extension if not exists pgcrypto;

create table public.bookchat_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', username text unique, email text,
 school text, department text, bio text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.bookchat_chats (
 id uuid primary key default gen_random_uuid(),
 participant_a uuid not null references auth.users(id) on delete cascade,
 participant_b uuid not null references auth.users(id) on delete cascade,
 last_message text, last_message_at timestamptz, created_at timestamptz not null default now(),
 check (participant_a <> participant_b), unique (participant_a, participant_b)
);
create index bookchat_chats_a_last_idx on public.bookchat_chats(participant_a,last_message_at desc);
create index bookchat_chats_b_last_idx on public.bookchat_chats(participant_b,last_message_at desc);
create table public.bookchat_messages (
 id uuid primary key default gen_random_uuid(),
 chat_id uuid not null references public.bookchat_chats(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 text text not null check(length(trim(text)) between 1 and 10000),
 delivered boolean not null default false, created_at timestamptz not null default now()
);
create index bookchat_messages_chat_created_idx on public.bookchat_messages(chat_id,created_at);
create index bookchat_messages_sender_idx on public.bookchat_messages(sender_id);
create table public.bookchat_friendships (
 id uuid primary key default gen_random_uuid(),
 requester_id uuid not null references auth.users(id) on delete cascade,
 addressee_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'PENDING' check(status in ('PENDING','ACCEPTED','DECLINED','BLOCKED')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(requester_id <> addressee_id), unique(requester_id,addressee_id)
);
create index bookchat_friendships_addressee_status_idx on public.bookchat_friendships(addressee_id,status);
create index bookchat_friendships_requester_status_idx on public.bookchat_friendships(requester_id,status);
create table public.bookchat_admin_roles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'ADMIN' check(role in ('OWNER_ADMIN','ADMIN','MODERATOR')),
 created_at timestamptz not null default now()
);
create table public.bookchat_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references auth.users(id) on delete cascade,
 reported_user_id uuid references auth.users(id) on delete set null,
 reason text not null check(length(trim(reason)) between 1 and 200), details text,
 status text not null default 'OPEN' check(status in ('OPEN','REVIEWING','RESOLVED','DISMISSED')),
 created_at timestamptz not null default now(), resolved_at timestamptz
);
create index bookchat_reports_status_created_idx on public.bookchat_reports(status,created_at desc);
create index bookchat_reports_reporter_idx on public.bookchat_reports(reporter_id);
create index bookchat_reports_reported_user_idx on public.bookchat_reports(reported_user_id);
create table public.bookchat_groups (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 120), description text,
 created_by uuid not null references auth.users(id) on delete cascade,
 is_private boolean not null default true, created_at timestamptz not null default now()
);
create index bookchat_groups_created_by_idx on public.bookchat_groups(created_by);
create table public.bookchat_group_members (
 group_id uuid not null references public.bookchat_groups(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'MEMBER' check(role in ('OWNER','ADMIN','MEMBER')),
 joined_at timestamptz not null default now(), primary key(group_id,user_id)
);
create index bookchat_group_members_user_idx on public.bookchat_group_members(user_id,joined_at desc);

create or replace function public.bookchat_is_admin()
returns boolean language sql stable security invoker set search_path = ''
as $$ select exists(select 1 from public.bookchat_admin_roles ar where ar.user_id=(select auth.uid())); $$;

alter table public.bookchat_profiles enable row level security;
alter table public.bookchat_chats enable row level security;
alter table public.bookchat_messages enable row level security;
alter table public.bookchat_friendships enable row level security;
alter table public.bookchat_admin_roles enable row level security;
alter table public.bookchat_reports enable row level security;
alter table public.bookchat_groups enable row level security;
alter table public.bookchat_group_members enable row level security;

grant select,insert,update on public.bookchat_profiles to authenticated;
grant select,insert,update on public.bookchat_chats to authenticated;
grant select,insert on public.bookchat_messages to authenticated;
grant select,insert,update on public.bookchat_friendships to authenticated;
grant select on public.bookchat_admin_roles to authenticated;
grant select,insert,update on public.bookchat_reports to authenticated;
grant select,insert,update,delete on public.bookchat_groups to authenticated;
grant select,insert,update,delete on public.bookchat_group_members to authenticated;
grant execute on function public.bookchat_is_admin() to authenticated;

create policy "profiles searchable by signed-in users" on public.bookchat_profiles for select to authenticated using(true);
create policy "users create own profile" on public.bookchat_profiles for insert to authenticated with check((select auth.uid())=id);
create policy "users update own profile" on public.bookchat_profiles for update to authenticated using((select auth.uid())=id) with check((select auth.uid())=id);
create policy "chat participants can read chats" on public.bookchat_chats for select to authenticated using((select auth.uid()) in(participant_a,participant_b));
create policy "users create chats as participant a" on public.bookchat_chats for insert to authenticated with check((select auth.uid())=participant_a and participant_b<>(select auth.uid()));
create policy "chat participants update chat metadata" on public.bookchat_chats for update to authenticated using((select auth.uid()) in(participant_a,participant_b)) with check((select auth.uid()) in(participant_a,participant_b));
create policy "chat participants read messages" on public.bookchat_messages for select to authenticated using(exists(select 1 from public.bookchat_chats c where c.id=chat_id and (select auth.uid()) in(c.participant_a,c.participant_b)));
create policy "chat participants send as themselves" on public.bookchat_messages for insert to authenticated with check(sender_id=(select auth.uid()) and exists(select 1 from public.bookchat_chats c where c.id=chat_id and (select auth.uid()) in(c.participant_a,c.participant_b)));
create policy "participants read friendship requests" on public.bookchat_friendships for select to authenticated using((select auth.uid()) in(requester_id,addressee_id));
create policy "users send friendship requests" on public.bookchat_friendships for insert to authenticated with check(requester_id=(select auth.uid()) and requester_id<>addressee_id and status='PENDING');
create policy "addressee responds to pending request" on public.bookchat_friendships for update to authenticated using(addressee_id=(select auth.uid()) and status='PENDING') with check(addressee_id=(select auth.uid()) and status in('ACCEPTED','DECLINED','BLOCKED'));
create policy "users read own admin role" on public.bookchat_admin_roles for select to authenticated using(user_id=(select auth.uid()));
create policy "users create reports" on public.bookchat_reports for insert to authenticated with check(reporter_id=(select auth.uid()));
create policy "reporter reads own reports" on public.bookchat_reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy "admins read all reports" on public.bookchat_reports for select to authenticated using(public.bookchat_is_admin());
create policy "admins update reports" on public.bookchat_reports for update to authenticated using(public.bookchat_is_admin()) with check(public.bookchat_is_admin());
create policy "group members read groups" on public.bookchat_groups for select to authenticated using(not is_private or created_by=(select auth.uid()) or exists(select 1 from public.bookchat_group_members gm where gm.group_id=id and gm.user_id=(select auth.uid())));
create policy "users create own groups" on public.bookchat_groups for insert to authenticated with check(created_by=(select auth.uid()));
create policy "group creator updates group" on public.bookchat_groups for update to authenticated using(created_by=(select auth.uid())) with check(created_by=(select auth.uid()));
create policy "group creator deletes group" on public.bookchat_groups for delete to authenticated using(created_by=(select auth.uid()));
create policy "users read own group membership" on public.bookchat_group_members for select to authenticated using(user_id=(select auth.uid()));
create policy "group creator adds members" on public.bookchat_group_members for insert to authenticated with check(exists(select 1 from public.bookchat_groups g where g.id=group_id and g.created_by=(select auth.uid())));
create policy "members leave groups" on public.bookchat_group_members for delete to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.bookchat_groups g where g.id=group_id and g.created_by=(select auth.uid())));

alter publication supabase_realtime add table public.bookchat_messages;
