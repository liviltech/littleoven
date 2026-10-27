-- Little Oven Supabase backend
-- Run in Supabase SQL Editor. Manager access is granted only through manager_roles.

create extension if not exists pgcrypto;
create sequence if not exists public.member_number_seq start 100001;

create table if not exists public.manager_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_manager()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.manager_roles where user_id = auth.uid());
$$;

create or replace function public.current_user_is_manager()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$ select public.is_manager(); $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  member_no text not null unique default ('LO' || lpad(nextval('public.member_number_seq')::text, 6, '0')),
  full_name text not null default '',
  email text not null default '',
  phone text not null default '',
  sex text not null default '',
  birthday date,
  status text not null default 'active' check (status in ('active','inactive','suspended')),
  points integer not null default 0 check (points >= 0),
  joined_at timestamptz not null default now(),
  last_active_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.point_transactions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  delta integer not null check (delta <> 0),
  reason text not null,
  branch text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  image_url text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  code text not null unique,
  title text not null,
  description text not null default '',
  discount_amount numeric(8,2) not null default 0 check (discount_amount >= 0),
  eligible_sizes integer[] not null default '{}',
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  status text not null default 'available' check (status in ('available','pending','redeemed','expired','void')),
  source text not null default 'manager' check (source in ('manager','birthday')),
  source_key text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  unique (member_id, source_key)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null,
  body text not null,
  sent_by uuid references auth.users(id) on delete set null,
  sent_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists profiles_birthday_idx on public.profiles (birthday);
create index if not exists profiles_status_activity_idx on public.profiles (status, last_active_at desc);
create index if not exists point_transactions_member_date_idx on public.point_transactions (member_id, created_at desc);
create index if not exists vouchers_member_status_idx on public.vouchers (member_id, status, expires_at);
create index if not exists messages_member_date_idx on public.messages (member_id, sent_at desc);
create index if not exists promotions_active_dates_idx on public.promotions (is_active, starts_at, ends_at);

create or replace function public.handle_new_member()
returns trigger language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, email, phone, sex, birthday)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'phone',''),
    coalesce(new.raw_user_meta_data->>'sex',''),
    nullif(new.raw_user_meta_data->>'birthday','')::date
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_littleoven on auth.users;
create trigger on_auth_user_created_littleoven
after insert on auth.users
for each row execute procedure public.handle_new_member();

create or replace function public.update_my_profile(
  p_full_name text, p_phone text, p_sex text, p_birthday date default null
)
returns public.profiles language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare result public.profiles;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.profiles
  set full_name = left(trim(coalesce(p_full_name,'')),120),
      phone = left(trim(coalesce(p_phone,'')),40),
      sex = left(trim(coalesce(p_sex,'')),40),
      birthday = case when birthday is null then p_birthday else birthday end,
      email = coalesce(auth.jwt()->>'email', email),
      updated_at = now()
  where id = auth.uid()
  returning * into result;
  if result.id is null then raise exception 'Member profile not found'; end if;
  return result;
end;
$$;

create or replace function public.touch_member_activity()
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles set last_active_at = now() where id = auth.uid();
end;
$$;

create or replace function public.ensure_birthday_voucher()
returns public.vouchers language plpgsql security definer
set search_path = public, pg_temp
as $$
declare p public.profiles; v public.vouchers; this_month integer; this_year integer;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into p from public.profiles where id = auth.uid() and status = 'active';
  if p.id is null then return null; end if;
  if p.birthday is null then return null; end if;
  this_month := extract(month from current_date)::integer;
  this_year := extract(year from current_date)::integer;
  if extract(month from p.birthday)::integer <> this_month then return null; end if;
  insert into public.vouchers (
    member_id, code, title, description, discount_amount, eligible_sizes,
    starts_at, expires_at, status, source, source_key
  )
  values (
    p.id,
    'BDAY-' || right(regexp_replace(p.member_no, '[^A-Za-z0-9]', '', 'g'), 4) || '-' || this_year || lpad(this_month::text, 2, '0') || '-' || upper(substr(encode(gen_random_bytes(3),'hex'),1,6)),
    'Birthday month RM20 cake voucher',
    'RM20 off any 8-inch or 10-inch whole cake. Walk in and show this voucher at the counter to claim.',
    20.00, array[8,10],
    date_trunc('month', now()),
    (date_trunc('month', now()) + interval '1 month' - interval '1 millisecond'),
    'available', 'birthday', 'birthday:' || this_year
  )
  on conflict (member_id, source_key) do nothing;
  select * into v from public.vouchers where member_id = p.id and source_key = 'birthday:' || this_year;
  return v;
end;
$$;

create or replace function public.manager_dashboard_summary()
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_manager() then raise exception 'Manager access required'; end if;
  return jsonb_build_object(
    'active_members', (select count(*) from public.profiles where status = 'active'),
    'members', (select count(*) from public.profiles),
    'birthdays_this_month', (select count(*) from public.profiles where status = 'active' and birthday is not null and extract(month from birthday) = extract(month from current_date)),
    'unread_messages', (select count(*) from public.messages where read_at is null)
  );
end;
$$;

create or replace function public.manager_adjust_points(
  p_member_id uuid, p_delta integer, p_reason text, p_branch text default null
)
returns public.profiles language plpgsql security definer
set search_path = public, pg_temp
as $$
declare result public.profiles;
begin
  if not public.is_manager() then raise exception 'Manager access required'; end if;
  if p_delta = 0 then raise exception 'Points adjustment cannot be zero'; end if;
  update public.profiles
  set points = points + p_delta, updated_at = now()
  where id = p_member_id and points + p_delta >= 0
  returning * into result;
  if result.id is null then raise exception 'Member not found or adjustment would make points negative'; end if;
  insert into public.point_transactions(member_id, delta, reason, branch, created_by)
  values (p_member_id, p_delta, left(trim(p_reason),200), nullif(left(trim(coalesce(p_branch,'')),120),''), auth.uid());
  return result;
end;
$$;

create or replace function public.manager_set_member_status(p_member_id uuid, p_status text)
returns public.profiles language plpgsql security definer
set search_path = public, pg_temp
as $$
declare result public.profiles;
begin
  if not public.is_manager() then raise exception 'Manager access required'; end if;
  if p_status not in ('active','inactive','suspended') then raise exception 'Invalid member status'; end if;
  update public.profiles set status = p_status, updated_at = now()
  where id = p_member_id returning * into result;
  if result.id is null then raise exception 'Member not found'; end if;
  return result;
end;
$$;

create or replace function public.manager_issue_voucher(
  p_title text, p_description text, p_discount_amount numeric,
  p_eligible_sizes integer[], p_expires_at timestamptz,
  p_member_id uuid default null, p_code_prefix text default 'LO'
)
returns integer language plpgsql security definer
set search_path = public, pg_temp
as $$
declare p record; issued integer := 0; prefix text;
begin
  if not public.is_manager() then raise exception 'Manager access required'; end if;
  if p_discount_amount < 0 then raise exception 'Discount cannot be negative'; end if;
  prefix := upper(left(regexp_replace(coalesce(p_code_prefix,'LO'), '[^A-Za-z0-9]', '', 'g'), 12));
  if prefix = '' then prefix := 'LO'; end if;
  for p in
    select id, member_no from public.profiles
    where status = 'active' and (p_member_id is null or id = p_member_id)
  loop
    insert into public.vouchers(member_id, code, title, description, discount_amount, eligible_sizes, expires_at, source, created_by)
    values (p.id, prefix || '-' || upper(substr(encode(gen_random_bytes(5),'hex'),1,10)), left(trim(p_title),120), left(trim(coalesce(p_description,'')),600), p_discount_amount, coalesce(p_eligible_sizes,'{}'), p_expires_at, 'manager', auth.uid());
    issued := issued + 1;
  end loop;
  if p_member_id is not null and issued = 0 then raise exception 'Active member not found'; end if;
  return issued;
end;
$$;

create or replace function public.manager_send_message(p_member_id uuid, p_subject text, p_body text)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
declare message_id uuid;
begin
  if not public.is_manager() then raise exception 'Manager access required'; end if;
  if not exists(select 1 from public.profiles where id = p_member_id) then raise exception 'Member not found'; end if;
  insert into public.messages(member_id,subject,body,sent_by)
  values (p_member_id,left(trim(p_subject),160),left(trim(p_body),5000),auth.uid())
  returning id into message_id;
  return message_id;
end;
$$;

create or replace function public.mark_message_read(p_message_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.messages set read_at = now()
  where id = p_message_id and member_id = auth.uid() and read_at is null;
end;
$$;

alter table public.manager_roles enable row level security;
alter table public.profiles enable row level security;
alter table public.point_transactions enable row level security;
alter table public.promotions enable row level security;
alter table public.vouchers enable row level security;
alter table public.messages enable row level security;

drop policy if exists manager_role_self_read on public.manager_roles;
create policy manager_role_self_read on public.manager_roles for select to authenticated using (user_id = auth.uid());
drop policy if exists profiles_read_self_or_manager on public.profiles;
create policy profiles_read_self_or_manager on public.profiles for select to authenticated using (id = auth.uid() or public.is_manager());
drop policy if exists point_transactions_read_self_or_manager on public.point_transactions;
create policy point_transactions_read_self_or_manager on public.point_transactions for select to authenticated using (member_id = auth.uid() or public.is_manager());
drop policy if exists promotions_read_live_or_manager on public.promotions;
create policy promotions_read_live_or_manager on public.promotions for select to authenticated using ((is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now())) or public.is_manager());
drop policy if exists promotions_manager_insert on public.promotions;
create policy promotions_manager_insert on public.promotions for insert to authenticated with check (public.is_manager());
drop policy if exists promotions_manager_update on public.promotions;
create policy promotions_manager_update on public.promotions for update to authenticated using (public.is_manager()) with check (public.is_manager());
drop policy if exists promotions_manager_delete on public.promotions;
create policy promotions_manager_delete on public.promotions for delete to authenticated using (public.is_manager());
drop policy if exists vouchers_read_self_or_manager on public.vouchers;
create policy vouchers_read_self_or_manager on public.vouchers for select to authenticated using (member_id = auth.uid() or public.is_manager());
drop policy if exists messages_read_self_or_manager on public.messages;
create policy messages_read_self_or_manager on public.messages for select to authenticated using (member_id = auth.uid() or public.is_manager());

grant select on public.manager_roles, public.profiles, public.point_transactions, public.promotions, public.vouchers, public.messages to authenticated;
grant insert, update, delete on public.promotions to authenticated;
grant usage, select on sequence public.member_number_seq to authenticated;
revoke all on function public.is_manager() from public;
revoke all on function public.current_user_is_manager() from public;
revoke all on function public.update_my_profile(text,text,text,date) from public;
revoke all on function public.touch_member_activity() from public;
revoke all on function public.ensure_birthday_voucher() from public;
revoke all on function public.manager_dashboard_summary() from public;
revoke all on function public.manager_adjust_points(uuid,integer,text,text) from public;
revoke all on function public.manager_set_member_status(uuid,text) from public;
revoke all on function public.manager_issue_voucher(text,text,numeric,integer[],timestamptz,uuid,text) from public;
revoke all on function public.manager_send_message(uuid,text,text) from public;
revoke all on function public.mark_message_read(uuid) from public;
grant execute on function public.is_manager() to authenticated;
grant execute on function public.current_user_is_manager() to authenticated;
grant execute on function public.update_my_profile(text,text,text,date) to authenticated;
grant execute on function public.touch_member_activity() to authenticated;
grant execute on function public.ensure_birthday_voucher() to authenticated;
grant execute on function public.manager_dashboard_summary() to authenticated;
grant execute on function public.manager_adjust_points(uuid,integer,text,text) to authenticated;
grant execute on function public.manager_set_member_status(uuid,text) to authenticated;
grant execute on function public.manager_issue_voucher(text,text,numeric,integer[],timestamptz,uuid,text) to authenticated;
grant execute on function public.manager_send_message(uuid,text,text) to authenticated;
grant execute on function public.mark_message_read(uuid) to authenticated;

-- After the first manager creates an account with Supabase Auth, run:
-- insert into public.manager_roles(user_id) values ('AUTH_USER_UUID');
