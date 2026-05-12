
-- Roles enum
create type public.app_role as enum ('admin', 'user');

-- User roles table (separate from any profile table)
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);

alter table public.user_roles enable row level security;

-- Security definer role check (avoids RLS recursion)
create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  )
$$;

-- RLS for user_roles
create policy "Users can view their own roles"
  on public.user_roles for select to authenticated
  using (auth.uid() = user_id);

create policy "Admins can view all roles"
  on public.user_roles for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

create policy "Admins can manage roles"
  on public.user_roles for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

-- Fare settings
create table public.fare_settings (
  id uuid primary key default gen_random_uuid(),
  ride_type text not null unique,
  base_price numeric not null default 0,
  price_per_km numeric not null default 0,
  currency text not null default 'GNF',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.fare_settings enable row level security;

create policy "Anyone can read fare settings"
  on public.fare_settings for select
  using (true);

create policy "Only admins can modify fare settings"
  on public.fare_settings for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

create or replace function public.touch_fare_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  return new;
end $$;

create trigger fare_settings_touch
before update on public.fare_settings
for each row execute function public.touch_fare_updated_at();

-- Seed default fares
insert into public.fare_settings (ride_type, base_price, price_per_km) values
  ('moto', 5000, 1000),
  ('toktok', 8000, 1500);
