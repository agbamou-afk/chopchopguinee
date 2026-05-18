-- Merchant stores
create table if not exists public.merchant_stores (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique,
  slug text not null unique,
  name text not null,
  avatar_url text,
  cover_url text,
  bio text,
  district text,
  category text,
  delivery_available boolean not null default false,
  choppay_enabled boolean not null default false,
  verification_state text not null default 'none' check (verification_state in ('none','pending','verified')),
  member_since timestamptz not null default now(),
  status text not null default 'active' check (status in ('active','paused','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists merchant_stores_owner_idx on public.merchant_stores(owner_user_id);
create index if not exists merchant_stores_district_idx on public.merchant_stores(district);

alter table public.merchant_stores enable row level security;

create policy "Anyone read active stores"
  on public.merchant_stores for select to anon, authenticated
  using (status = 'active' or owner_user_id = auth.uid() or has_role(auth.uid(),'admin'::app_role));

create policy "Owner upserts own store"
  on public.merchant_stores for insert to authenticated
  with check (owner_user_id = auth.uid());

create policy "Owner updates own store"
  on public.merchant_stores for update to authenticated
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());

create policy "Admins manage stores"
  on public.merchant_stores for all to authenticated
  using (has_role(auth.uid(),'admin'::app_role))
  with check (has_role(auth.uid(),'admin'::app_role));

-- Extend listings
alter table public.marketplace_listings
  add column if not exists store_id uuid references public.merchant_stores(id) on delete set null,
  add column if not exists promoted boolean not null default false,
  add column if not exists sold_count integer not null default 0;

create index if not exists marketplace_listings_store_idx on public.marketplace_listings(store_id);
create index if not exists marketplace_listings_created_idx on public.marketplace_listings(created_at desc);

-- Listing metrics
create table if not exists public.listing_metrics (
  listing_id uuid primary key references public.marketplace_listings(id) on delete cascade,
  views integer not null default 0,
  clicks integer not null default 0,
  saves integer not null default 0,
  messages integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.listing_metrics enable row level security;

create policy "Owner reads own listing metrics"
  on public.listing_metrics for select to authenticated
  using (exists (select 1 from public.marketplace_listings l where l.id = listing_metrics.listing_id and l.seller_id = auth.uid()));

create policy "Admins read listing metrics"
  on public.listing_metrics for select to authenticated
  using (has_role(auth.uid(),'admin'::app_role));

-- Listing saves
create table if not exists public.listing_saves (
  user_id uuid not null,
  listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);
create index if not exists listing_saves_listing_idx on public.listing_saves(listing_id);

alter table public.listing_saves enable row level security;

create policy "Users manage own saves"
  on public.listing_saves for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Admins read saves"
  on public.listing_saves for select to authenticated
  using (has_role(auth.uid(),'admin'::app_role));

-- RPCs
create or replace function public.marche_increment_listing_metric(_listing_id uuid, _kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if _kind not in ('view','click','save','message') then
    raise exception 'invalid metric kind';
  end if;
  insert into public.listing_metrics (listing_id) values (_listing_id)
    on conflict (listing_id) do nothing;
  if _kind = 'view' then
    update public.listing_metrics set views = views + 1, updated_at = now() where listing_id = _listing_id;
  elsif _kind = 'click' then
    update public.listing_metrics set clicks = clicks + 1, updated_at = now() where listing_id = _listing_id;
  elsif _kind = 'save' then
    update public.listing_metrics set saves = saves + 1, updated_at = now() where listing_id = _listing_id;
  elsif _kind = 'message' then
    update public.listing_metrics set messages = messages + 1, updated_at = now() where listing_id = _listing_id;
  end if;
end;
$$;

grant execute on function public.marche_increment_listing_metric(uuid, text) to anon, authenticated;

create or replace function public.marche_toggle_listing_save(_listing_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  _uid uuid := auth.uid();
  _existed boolean;
begin
  if _uid is null then raise exception 'auth required'; end if;
  insert into public.listing_metrics (listing_id) values (_listing_id) on conflict do nothing;
  if exists (select 1 from public.listing_saves where user_id = _uid and listing_id = _listing_id) then
    delete from public.listing_saves where user_id = _uid and listing_id = _listing_id;
    update public.listing_metrics set saves = greatest(saves - 1, 0), updated_at = now() where listing_id = _listing_id;
    return false;
  else
    insert into public.listing_saves (user_id, listing_id) values (_uid, _listing_id);
    update public.listing_metrics set saves = saves + 1, updated_at = now() where listing_id = _listing_id;
    return true;
  end if;
end;
$$;

grant execute on function public.marche_toggle_listing_save(uuid) to authenticated;

-- Auto-update updated_at on merchant_stores
create or replace function public.merchant_stores_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

drop trigger if exists merchant_stores_touch on public.merchant_stores;
create trigger merchant_stores_touch before update on public.merchant_stores
  for each row execute function public.merchant_stores_touch_updated_at();