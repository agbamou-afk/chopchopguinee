
-- Enums
do $$ begin
  create type public.message_channel as enum ('whatsapp', 'sms', 'inapp');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_status as enum ('queued', 'sending', 'sent', 'delivered', 'read', 'failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_template as enum (
    'otp_code',
    'welcome',
    'topup_pending',
    'topup_success',
    'payment_success',
    'refund',
    'ride_confirmed',
    'driver_assigned',
    'delivery_completed',
    'suspicious_activity'
  );
exception when duplicate_object then null; end $$;

-- Notification preferences
create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  whatsapp_enabled boolean not null default true,
  sms_enabled boolean not null default true,
  topic_otp boolean not null default true,
  topic_wallet boolean not null default true,
  topic_ride boolean not null default true,
  topic_marketing boolean not null default false,
  preferred_channel public.message_channel not null default 'whatsapp',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "Users read own prefs" on public.notification_preferences;
create policy "Users read own prefs" on public.notification_preferences
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users upsert own prefs" on public.notification_preferences;
create policy "Users upsert own prefs" on public.notification_preferences
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users update own prefs" on public.notification_preferences;
create policy "Users update own prefs" on public.notification_preferences
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Admins manage prefs" on public.notification_preferences;
create policy "Admins manage prefs" on public.notification_preferences
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

drop trigger if exists trg_notif_prefs_touch on public.notification_preferences;
create trigger trg_notif_prefs_touch before update on public.notification_preferences
  for each row execute function public.update_updated_at_column();

-- Outbound message log
create table if not exists public.message_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  to_address text not null,
  channel public.message_channel not null,
  provider text not null,
  template public.message_template not null,
  payload jsonb not null default '{}'::jsonb,
  body text not null,
  status public.message_status not null default 'queued',
  provider_message_id text,
  error text,
  retry_count integer not null default 0,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz
);

create index if not exists message_log_user_idx on public.message_log(user_id, created_at desc);
create index if not exists message_log_status_idx on public.message_log(status);

alter table public.message_log enable row level security;

drop policy if exists "Users read own messages" on public.message_log;
create policy "Users read own messages" on public.message_log
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Admins manage messages" on public.message_log;
create policy "Admins manage messages" on public.message_log
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));
