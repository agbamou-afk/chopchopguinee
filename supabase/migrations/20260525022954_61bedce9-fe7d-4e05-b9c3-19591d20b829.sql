
-- Support / Issues spine for CHOPCHOP pilot
do $$ begin
  create type public.support_issue_type as enum (
    'payment_pending','payment_failed','courier_no_show','merchant_not_ready',
    'customer_unreachable','wrong_address','package_dispute','item_not_available',
    'delivery_failed','app_bug','account_issue','safety_concern','other'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.support_issue_status as enum (
    'open','in_review','waiting_on_user','waiting_on_courier','waiting_on_merchant',
    'resolved','escalated','cancelled'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.support_issue_severity as enum ('low','medium','high','critical');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.support_issue_role as enum (
    'support','operations','payment','merchant','courier','admin'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.support_issues (
  id uuid primary key default gen_random_uuid(),
  issue_type public.support_issue_type not null,
  status public.support_issue_status not null default 'open',
  severity public.support_issue_severity not null default 'medium',
  title text not null,
  description text,
  district text,
  reporter_user_id uuid,
  assigned_role public.support_issue_role not null default 'support',
  related_mission_id uuid,
  related_payment_intent_id uuid,
  related_food_order_id uuid,
  related_market_listing_id uuid,
  related_store_id uuid,
  related_restaurant_id uuid,
  related_driver_id uuid,
  related_customer_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists support_issues_status_idx on public.support_issues(status);
create index if not exists support_issues_type_idx on public.support_issues(issue_type);
create index if not exists support_issues_district_idx on public.support_issues(district);
create index if not exists support_issues_reporter_idx on public.support_issues(reporter_user_id);
create index if not exists support_issues_mission_idx on public.support_issues(related_mission_id);
create index if not exists support_issues_payment_idx on public.support_issues(related_payment_intent_id);
create index if not exists support_issues_created_idx on public.support_issues(created_at desc);

create or replace function public.support_issues_touch_updated()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  if (new.status in ('resolved','cancelled')) and (old.status is distinct from new.status) and new.resolved_at is null then
    new.resolved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists support_issues_touch on public.support_issues;
create trigger support_issues_touch
before update on public.support_issues
for each row execute function public.support_issues_touch_updated();

alter table public.support_issues enable row level security;

-- Reporter can read their own issues
drop policy if exists "Reporters read own issues" on public.support_issues;
create policy "Reporters read own issues"
on public.support_issues for select
to authenticated
using (auth.uid() = reporter_user_id);

-- Courier can read issues linked to their missions or as related_driver
drop policy if exists "Couriers read mission issues" on public.support_issues;
create policy "Couriers read mission issues"
on public.support_issues for select
to authenticated
using (
  auth.uid() = related_driver_id
  or (
    related_mission_id is not null
    and exists (
      select 1 from public.missions m
      where m.id = related_mission_id and m.courier_id = auth.uid()
    )
  )
);

-- Merchant can read issues linked to their restaurant / store / food order
drop policy if exists "Merchants read own issues" on public.support_issues;
create policy "Merchants read own issues"
on public.support_issues for select
to authenticated
using (
  (related_restaurant_id is not null and exists (
    select 1 from public.food_restaurants r where r.id = related_restaurant_id and r.owner_user_id = auth.uid()
  ))
  or (related_food_order_id is not null and exists (
    select 1 from public.food_orders o
    join public.food_restaurants r on r.id = o.restaurant_id
    where o.id = related_food_order_id and r.owner_user_id = auth.uid()
  ))
  or (related_store_id is not null and exists (
    select 1 from public.merchant_stores s where s.id = related_store_id and s.owner_user_id = auth.uid()
  ))
);

-- Admins read all
drop policy if exists "Admins read all issues" on public.support_issues;
create policy "Admins read all issues"
on public.support_issues for select
to authenticated
using (is_any_admin(auth.uid()));

-- Authenticated users can create issues that they own as reporter
drop policy if exists "Users create own issues" on public.support_issues;
create policy "Users create own issues"
on public.support_issues for insert
to authenticated
with check (reporter_user_id = auth.uid());

-- Admins can create on behalf of anyone
drop policy if exists "Admins create issues" on public.support_issues;
create policy "Admins create issues"
on public.support_issues for insert
to authenticated
with check (is_any_admin(auth.uid()));

-- Only admins update / manage issues
drop policy if exists "Admins update issues" on public.support_issues;
create policy "Admins update issues"
on public.support_issues for update
to authenticated
using (is_any_admin(auth.uid()))
with check (is_any_admin(auth.uid()));
