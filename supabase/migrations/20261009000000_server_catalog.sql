-- ═════════════════════════════════════════════════════════════════════════
-- REPERI — server-driven catalog, pricing & assignment
--
-- Creates:
--   app_settings            global knobs (pickup fee, review mode, service area)
--   services                every package: name, price, features, routing
--   assignment_pools        who can receive work + rotation batch + counter
--   assignment_pool_members the garages / delivery partners / washers in a pool
--   review_overrides        App Store review account → fixed demo partners
--   payment_intents         server-priced checkout → booking (idempotent)
--   next_pool_member()      atomic rotation (no race between two bookings)
--   claim_payment_intent()  lock so confirm + webhook never double-book
--
-- Safe to run more than once: every create / insert is "if not exists" /
-- "on conflict do nothing", so re-running never overwrites prices or pool
-- members you've edited in the dashboard.
-- ═════════════════════════════════════════════════════════════════════════


-- ── updated_at helper ──────────────────────────────────────────────────
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ── 1. app_settings ────────────────────────────────────────────────────
create table if not exists public.app_settings (
  key         text primary key,
  value       jsonb not null,
  is_public   boolean not null default false,   -- readable by the app
  description text,
  updated_at  timestamptz not null default now()
);
drop trigger if exists app_settings_touch on public.app_settings;
create trigger app_settings_touch before update on public.app_settings
  for each row execute function public.touch_updated_at();

insert into public.app_settings (key, value, is_public, description) values
  ('pickup_drop_fee', '100', true,
   'Doorstep pickup & drop fee in rupees, added when the customer opts in (or always, for "locked" services like Roadside).'),
  ('review_override_enabled', 'true', false,
   'While true, bookings by accounts listed in review_overrides go to the fixed demo garage / delivery partner / washer. Turn off after App Store approval.'),
  ('service_area', '{"lat": 12.9716, "lng": 77.5946, "radius_km": 100}', true,
   'Bookings are only accepted for addresses inside this circle (centre + radius in km).')
on conflict (key) do nothing;

-- ── 2. services ────────────────────────────────────────────────────────
create table if not exists public.services (
  key              text primary key check (key ~ '^[a-z0-9_]+$'),
  name             text not null,
  booking_name     text,                 -- saved as package_name on the booking; defaults to name
  category         text,                 -- grouping on the Services screen, e.g. 'Periodic Servicing'
  screens          text[] not null default '{}',   -- in-app screens that list it, e.g. {servicing}
  vehicle_type     text not null default 'car' check (vehicle_type in ('car','bike','any')),
  tagline          text,                 -- short line (Services screen / search / AI advisor)
  description      text,                 -- longer line on the package's own screen
  price            integer check (price is null or price >= 0),   -- rupees; null = quote only
  price_label      text,                 -- shown instead of price when set, e.g. 'Custom Quote'
  duration         text,
  badge            text,                 -- e.g. 'Most Popular', 'Recommended'
  popular          boolean not null default false,
  features         jsonb not null default '[]'::jsonb,   -- ["Engine Oil Change", ...]
  details          jsonb not null default '{}'::jsonb,   -- screen-specific extras
  sort_order       integer not null default 0,
  active           boolean not null default true,        -- false = hidden everywhere
  show_in_catalog  boolean not null default true,        -- listed on the Services screen
  is_addon         boolean not null default false,       -- only bookable together with a main package
  -- booking behaviour ----------------------------------------------------
  bookable         boolean not null default true,        -- false = display / enquiry only
  booking_table    text check (booking_table in
                     ('bookings','pollution_booking','inspection_booking','claim_table','monthlywash_table')),
  vehicle_required boolean not null default true,
  pickup_mode      text not null default 'optional'
                     check (pickup_mode in ('optional','none','included','locked')),
  allow_cod        boolean not null default true,
  admin_pool       text,   -- garage pool; 'garage_{vehicle}' = by the booked vehicle's type
  delivery_pool    text,   -- used only when the booking has pickup & drop
  washer_pool      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint bookable_needs_table check (not bookable or booking_table is not null)
);
create index if not exists services_screens_idx on public.services using gin (screens);
drop trigger if exists services_touch on public.services;
create trigger services_touch before update on public.services
  for each row execute function public.touch_updated_at();

comment on column public.services.pickup_mode is
  'optional = customer chooses (+fee) · none = no pickup (doorstep/at-home services) · included = always pickup, no fee · locked = always pickup, fee charged';

-- ── 3. assignment pools ────────────────────────────────────────────────
create table if not exists public.assignment_pools (
  key         text primary key check (key ~ '^[a-z0-9_]+$'),
  role        text not null check (role in ('admin','delivery','washer')),
  batch_size  integer not null default 1 check (batch_size >= 1),  -- bookings each member gets before rotating
  counter     bigint not null default 0,                            -- bookings assigned so far
  active      boolean not null default true,
  description text,
  updated_at  timestamptz not null default now()
);
drop trigger if exists assignment_pools_touch on public.assignment_pools;
create trigger assignment_pools_touch before update on public.assignment_pools
  for each row execute function public.touch_updated_at();

create table if not exists public.assignment_pool_members (
  pool_key   text not null references public.assignment_pools(key) on delete cascade,
  member_ref text not null,          -- admin.id (uuid) / delivery_partners.id / washers.id
  label      text,                   -- human-readable, e.g. the admin username
  position   integer not null default 0,
  active     boolean not null default true,
  primary key (pool_key, member_ref)
);

-- ── 4. review overrides ────────────────────────────────────────────────
create table if not exists public.review_overrides (
  customer_email text not null,
  role           text not null check (role in ('admin','delivery','washer')),
  member_ref     text not null,
  label          text,
  primary key (customer_email, role)
);

-- ── 5. payment intents ─────────────────────────────────────────────────
create table if not exists public.payment_intents (
  id                    uuid primary key default gen_random_uuid(),
  kind                  text not null default 'service' check (kind in ('service','fleet')),
  user_id               uuid,
  customer_email        text,
  vehicle_id            text,
  items                 jsonb not null default '[]'::jsonb,   -- [{key, name, price}]
  options               jsonb not null default '{}'::jsonb,
  pickup_drop           boolean not null default false,
  pickup_fee            integer not null default 0,
  subtotal              integer not null,                     -- rupees, excl. pickup fee
  amount                integer not null check (amount >= 0), -- rupees charged
  currency              text not null default 'INR',
  payment_method        text not null check (payment_method in ('online','cod')),
  status                text not null default 'created'
                          check (status in ('created','processing','booked','failed')),
  razorpay_order_id     text unique,
  razorpay_payment_id   text,
  booking_table         text,
  booking_id            text,
  error                 text,
  attempts              integer not null default 0,
  processing_started_at timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists payment_intents_user_idx on public.payment_intents (user_id, created_at desc);
drop trigger if exists payment_intents_touch on public.payment_intents;
create trigger payment_intents_touch before update on public.payment_intents
  for each row execute function public.touch_updated_at();

-- ── 6. Row level security ──────────────────────────────────────────────
-- The app may READ active services and public settings. Everything else is
-- only touched by the booking-api Edge Function (service role key).
alter table public.app_settings            enable row level security;
alter table public.services                enable row level security;
alter table public.assignment_pools        enable row level security;
alter table public.assignment_pool_members enable row level security;
alter table public.review_overrides        enable row level security;
alter table public.payment_intents         enable row level security;

drop policy if exists "services readable" on public.services;
create policy "services readable" on public.services
  for select to anon, authenticated using (active);

drop policy if exists "public settings readable" on public.app_settings;
create policy "public settings readable" on public.app_settings
  for select to anon, authenticated using (is_public);

drop policy if exists "own payment intents readable" on public.payment_intents;
create policy "own payment intents readable" on public.payment_intents
  for select to authenticated using (user_id = auth.uid());

-- ── 7. Atomic rotation ─────────────────────────────────────────────────
-- Each call bumps the pool's counter under a row lock, so two bookings
-- arriving at the same moment can never both land on the same member.
-- Member index = (counter / batch_size) mod active_member_count.
create or replace function public.next_pool_member(p_pool text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_counter bigint;
  v_batch   integer;
  v_n       integer;
  v_ref     text;
begin
  -- lock the pool row first, then count members under that lock
  select counter, batch_size into v_counter, v_batch
    from assignment_pools
   where key = p_pool and active
   for update;
  if not found then
    return null;
  end if;

  select count(*) into v_n
    from assignment_pool_members
   where pool_key = p_pool and active;
  if v_n = 0 then
    return null;
  end if;

  select member_ref into v_ref
    from assignment_pool_members
   where pool_key = p_pool and active
   order by position, member_ref
   offset ((v_counter / v_batch) % v_n)
   limit 1;

  update assignment_pools set counter = counter + 1 where key = p_pool;
  return v_ref;
end $$;

revoke all on function public.next_pool_member(text) from public, anon, authenticated;

-- ── 8. Payment-intent lock (confirm + webhook can race) ────────────────
-- Returns the intent only to the ONE caller allowed to create its booking:
-- fresh ('created'), previously 'failed', or stuck 'processing' > 2 min.
create or replace function public.claim_payment_intent(p_intent uuid, p_payment_id text)
returns setof public.payment_intents
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update payment_intents
     set status = 'processing',
         processing_started_at = now(),
         attempts = attempts + 1,
         razorpay_payment_id = coalesce(p_payment_id, razorpay_payment_id),
         error = null
   where id = p_intent
     and (status in ('created','failed')
          or (status = 'processing' and processing_started_at < now() - interval '2 minutes'))
  returning *;
end $$;

revoke all on function public.claim_payment_intent(uuid, text) from public, anon, authenticated;
-- ═════════════════════════════════════════════════════════════════════════
-- Seed: assignment pools — reproduces today's in-app routing exactly
-- ═════════════════════════════════════════════════════════════════════════
--   garage_four_wheeler  admins with admin.vehicle = 'four wheeler', 3 each
--   garage_two_wheeler   admins with admin.vehicle = 'two wheeler', 3 each
--   garage_any           every admin, 3 each (bookings with no vehicle type)
--   garage_emergency     'emergency_service' (Roadside Assistance)
--   garage_claims        the claims garage (newexpert_care)
--   delivery_main        delivery partners 1, 2 alternating (pickup & drop)
--   delivery_dedicated   delivery partner 3 (pollution / inspection / claims)
--   washers_main         washers 1, 2 alternating (₹149–₹599 doorstep washes)
--   washers_subscriptions  empty on purpose — monthly plans are assigned by
--                          hand today (only the review account gets a washer)
-- Counters start where today's count-based rotation would be, so the very
-- next booking goes to the same partner the old app would have picked.

insert into public.assignment_pools (key, role, batch_size, description) values
  ('garage_four_wheeler',   'admin',    3, 'Car garages — each gets 3 bookings before rotating'),
  ('garage_two_wheeler',    'admin',    3, 'Bike garages — each gets 3 bookings before rotating'),
  ('garage_any',            'admin',    3, 'All garages — for bookings with no vehicle type'),
  ('garage_emergency',      'admin',    1, 'Roadside Assistance technician'),
  ('garage_claims',         'admin',    1, 'Insurance claims garage'),
  ('delivery_main',         'delivery', 1, 'Pickup & drop for regular bookings'),
  ('delivery_dedicated',    'delivery', 1, 'Pickup & drop for pollution, inspection and claims'),
  ('washers_main',          'washer',   1, 'Doorstep one-time washes (car ₹299/₹599, bike ₹149/₹299)'),
  ('washers_subscriptions', 'washer',   1, 'Monthly wash plans — add washers here to auto-assign them')
on conflict (key) do nothing;

-- Garage pools from the admin table (same ordering as today: by id).
insert into public.assignment_pool_members (pool_key, member_ref, label, position)
select 'garage_four_wheeler', a.id::text, a.username, row_number() over (order by a.id)
  from public.admin a where a.vehicle = 'four wheeler'
on conflict do nothing;

insert into public.assignment_pool_members (pool_key, member_ref, label, position)
select 'garage_two_wheeler', a.id::text, a.username, row_number() over (order by a.id)
  from public.admin a where a.vehicle = 'two wheeler'
on conflict do nothing;

insert into public.assignment_pool_members (pool_key, member_ref, label, position)
select 'garage_any', a.id::text, a.username, row_number() over (order by a.id)
  from public.admin a
on conflict do nothing;

insert into public.assignment_pool_members (pool_key, member_ref, label, position)
select 'garage_emergency', a.id::text, a.username, 1
  from public.admin a where a.username = 'emergency_service'
on conflict do nothing;

insert into public.assignment_pool_members (pool_key, member_ref, label, position)
select 'garage_claims', a.id::text, a.username, 1
  from public.admin a where a.id::text = '1bcf9d81-6625-4c01-ac23-f0c237462eb7'
on conflict do nothing;

insert into public.assignment_pool_members (pool_key, member_ref, label, position) values
  ('delivery_main',      '1', 'Delivery partner 1', 1),
  ('delivery_main',      '2', 'Delivery partner 2', 2),
  ('delivery_dedicated', '3', 'Delivery partner 3', 1),
  ('washers_main',       '1', 'Washer 1', 1),
  ('washers_main',       '2', 'Washer 2', 2)
on conflict do nothing;

-- Start each rotation where the old count-based logic left off (only on
-- first run — a pool that has already been used keeps its own counter).
update public.assignment_pools p set counter = (
  select count(*) from public.bookings b
   where b.assigned_to_admin_id::text in
         (select m.member_ref from public.assignment_pool_members m where m.pool_key = p.key)
) where p.key in ('garage_four_wheeler','garage_two_wheeler','garage_any') and p.counter = 0;

update public.assignment_pools set counter = (select count(*) from public.bookings)
 where key = 'delivery_main' and counter = 0;

update public.assignment_pools set counter = (select count(*) from public.bookings where washer_id is not null)
 where key = 'washers_main' and counter = 0;

-- ═════════════════════════════════════════════════════════════════════════
-- Seed: App Store review account → fixed demo partners (same as the app's
-- AppleReviewAssignmentOverride today). Toggle with app_settings
-- 'review_override_enabled'.
-- ═════════════════════════════════════════════════════════════════════════
insert into public.review_overrides (customer_email, role, member_ref, label)
select 'appreview@gmail.com', 'admin', a.id::text, a.username
  from public.admin a where a.username = 'appreview@gmail.com'
on conflict do nothing;

insert into public.review_overrides (customer_email, role, member_ref, label)
select 'appreview@gmail.com', 'delivery', d.id::text, d.email
  from public.delivery_partners d where d.email = 'delivery_apple@gmail.com'
on conflict do nothing;

insert into public.review_overrides (customer_email, role, member_ref, label)
select 'appreview@gmail.com', 'washer', w.id::text, w.email
  from public.washers w where w.email = 'washer_apple@gmail.com'
on conflict do nothing;
-- ═════════════════════════════════════════════════════════════════════════
-- Seed: every package in the app, with exactly the prices, wording and
-- routing the app uses today. Edit rows in Table Editor to change prices /
-- names / features — no app update needed.
-- ═════════════════════════════════════════════════════════════════════════
insert into public.services (key, name, booking_name, category, screens, vehicle_type, tagline, description, price, price_label, duration, badge, popular, features, details, sort_order, show_in_catalog, is_addon, bookable, booking_table, vehicle_required, pickup_mode, allow_cod, admin_pool, delivery_pool, washer_pool) values
  ('svc_essential', 'Essential', 'ESSENTIAL', 'Periodic Servicing', array['servicing']::text[], 'car', 'Perfect for routine service.', 'Perfect for routine service', 999, null, '3-4 hrs', null, false, '["Engine Oil Change", "Oil Filter Change", "Brake Inspection", "AC Cooling Check", "Battery Health Test", "Tyre Inspection", "Fluid Level Check", "21-Point Diagnostics", "Digital Health Report"]'::jsonb, '{}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('svc_premium_care', 'Premium Care', 'PREMIUM CARE', 'Periodic Servicing', array['servicing']::text[], 'car', 'Most Popular — everyday maintenance done right.', 'Most Popular', 3999, null, '3-4 hrs', 'Most Popular', true, '["Everything in Essential", "Premium Engine Oil", "Oil Filter Replacement", "Brake Fluid Top-up", "AC Performance Service", "Air Filter Cleaning", "Cabin Filter Cleaning", "Steering Check", "Suspension Check", "Car Wash", "Interior Vacuum", "35-Point Diagnostics"]'::jsonb, '{}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('svc_signature', 'Signature Service', 'SIGNATURE SERVICE', 'Periodic Servicing', array['servicing']::text[], 'car', 'Ultimate Protection.', 'Ultimate Protection', 5999, null, '3-4 hrs', null, false, '["Everything in Premium", "Synthetic Engine Oil", "Brake Fluid Replacement", "Air Filter Replacement", "Cabin Filter Replacement", "Battery Load Test", "Fuel System Check", "Complete Brake Service", "Wheel Alignment Check", "Underbody Inspection", "Deep Interior Cleaning", "Foam Exterior Wash", "50+ Point Diagnostics", "Photo Health Report", "Priority Support"]'::jsonb, '{}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('book_quick_service', 'Quick Service', 'Quick Service', 'Periodic Servicing', array['book_service']::text[], 'car', 'A fast maintenance package for regular upkeep and smoother daily performance.', 'A fast maintenance package designed for regular upkeep and smoother daily performance.', 1999, null, '90 mins', null, false, '["Engine oil replacement", "Oil filter cleaning", "Brake inspection", "Fluid top-up", "Battery check"]'::jsonb, '{}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('book_full_service', 'Full Service', 'Full Service', 'Periodic Servicing', array['book_service']::text[], 'car', 'Comprehensive servicing covering all major systems for peak performance.', 'Comprehensive servicing package covering all major systems of the vehicle for peak performance.', 4999, null, '4 hrs', null, false, '["Complete engine inspection", "Full oil replacement", "Air filter replacement", "Wheel balancing", "Suspension check", "Brake servicing"]'::jsonb, '{}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('book_ac_service', 'AC Service', 'AC Service', 'Periodic Servicing', array['book_service']::text[], 'car', 'Deep AC inspection and cooling optimization for maximum comfort.', 'Deep AC inspection and cooling optimization to ensure maximum comfort and airflow.', 2499, null, '2 hrs', null, false, '["AC gas refill", "Cooling efficiency check", "Cabin filter cleaning", "Vent sanitization", "Leak inspection"]'::jsonb, '{}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('book_engine_diagnostics', 'Engine Diagnostics', 'Engine Diagnostics', 'Periodic Servicing', array['book_service']::text[], 'car', 'Advanced computer diagnostics to find hidden engine and electrical issues.', 'Advanced computer diagnostics to identify hidden engine and electrical issues.', 1499, null, '45 mins', null, false, '["OBD scan", "Engine health report", "Sensor diagnostics", "Error code detection", "Performance analysis"]'::jsonb, '{}'::jsonb, 40, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('ac_service', 'AC Service', 'AC SERVICE', 'Periodic Servicing', array['ac']::text[], 'car', 'Complete AC inspection and cooling refresh', 'Complete AC inspection and cooling refresh', 1500, null, '1-2 hrs', null, false, '["AC System Inspection", "AC Gas Pressure Check", "AC Filter Cleaning", "AC Evaporator Cleaning", "AC Condenser Cleaning", "AC Vent Cleaning", "AC Sanitization", "Cooling Performance Check", "Leak Inspection"]'::jsonb, '{"best_for": "Regular maintenance and early signs of reduced cooling."}'::jsonb, 10, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('ac_premium_service', 'Premium AC Service', 'PREMIUM AC SERVICE', 'Periodic Servicing', array['ac']::text[], 'car', 'Deep clean, recharge, and odour-free cooling', 'Deep clean, recharge, and odour-free cooling', 2500, null, '1-2 hrs', 'Most Popular', true, '["Everything in ₹1,500 Package", "AC Deep Cleaning", "AC Gas Top-up", "AC Evaporator Deep Cleaning", "AC Condenser Deep Cleaning", "AC Blower Cleaning", "AC Sanitization", "AC Odour & Bacteria Treatment", "Cooling Performance Optimization", "Complete AC System Inspection"]'::jsonb, '{"best_for": "Poor cooling, bad odour, or complete AC care."}'::jsonb, 20, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('wash_express', 'Express Wash', 'EXPRESS WASH', 'Car Wash & Cleaning', array['washing']::text[], 'car', 'A quick refresh for your car.', 'A quick refresh for your car', 299, null, '1-2 hrs', null, false, '["High-Pressure Exterior Wash", "Premium Foam Wash", "Microfiber Hand Drying", "Tyre Cleaning", "Alloy Wheel Cleaning", "Exterior Glass Cleaning", "Tyre Shine Dressing", "Final Quality Inspection"]'::jsonb, '{"best_for": "Weekly cleaning or after a long drive."}'::jsonb, 10, true, false, true, 'bookings', true, 'none', true, null, null, 'washers_main'),
  ('wash_premium', 'Premium Wash', 'PREMIUM WASH', 'Car Wash & Cleaning', array['washing']::text[], 'car', 'Inside & out, clean and refreshed.', 'Inside & out, clean and refreshed', 599, null, '1-2 hrs', 'Most Popular', true, '["Everything in Express Wash", "Interior Vacuum Cleaning", "Dashboard & Console Cleaning", "Door Panel Wipe Down", "Interior Glass Cleaning", "Floor Mat Cleaning", "Boot (Trunk) Vacuum", "Air Freshener Application", "Plastic Trim Dressing", "Final Quality Inspection"]'::jsonb, '{"best_for": "Monthly maintenance and everyday use."}'::jsonb, 20, true, false, true, 'bookings', true, 'none', true, null, null, 'washers_main'),
  ('wash_signature_detailing', 'Signature Detailing', 'SIGNATURE DETAILING', 'Car Wash & Cleaning', array['washing']::text[], 'car', 'Restore your car''s showroom shine.', 'Restore your car''s showroom shine', 2999, null, '1-2 hrs', null, false, '["Everything in Premium Wash", "Snow Foam Pre-Wash", "Two-Bucket Safe Hand Wash", "Bug & Tar Removal", "Clay Bar Surface Decontamination", "Machine Wax / Paint Sealant Application", "Exterior Plastic Trim Restoration", "Tyre & Alloy Deep Cleaning", "Engine Bay Surface Cleaning", "Interior Deep Vacuum", "Leather/Fabric Seat Cleaning", "Dashboard UV Protection", "Door Jamb Cleaning", "Interior Steam Sanitization (where applicable)", "Premium Glass Treatment", "Long-Lasting Air Freshener", "Final Multi-Point Quality Inspection"]'::jsonb, '{"best_for": "Festive seasons, before resale, special occasions, or when you want your car looking its absolute best."}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('car_spa_quick_refresh', 'Quick Refresh', 'QUICK REFRESH', 'Car Wash & Cleaning', array['car_spa']::text[], 'car', 'Fast maintenance with essential exterior and basic interior cleaning.', 'Fast maintenance with essential exterior and basic interior cleaning.', 399, null, '30 mins', null, false, '["Pressure Water Wash", "pH Neutral Foam Wash", "Exterior Hand Wash", "Microfiber Drying", "Tyre Cleaning", "Tyre Polish", "Wheel Rim Cleaning", "Exterior Glass Cleaning", "Dashboard Dusting", "Interior Vacuum Cleaning", "Door Jamb Cleaning", "Final Quality Inspection"]'::jsonb, '{"subtitle": "Exterior Basic Care"}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('car_spa_premium', 'Premium Spa', 'PREMIUM SPA', 'Car Wash & Cleaning', array['car_spa']::text[], 'car', 'Everything in Quick Refresh, plus deep interior cleaning and protective treatments.', 'Everything in Quick Refresh, plus deep interior cleaning and protective treatments.', 999, null, '90 mins', null, false, '["Pressure Water Wash", "Premium Foam Wash", "Exterior Hand Drying", "Complete Interior Vacuum", "Dashboard Detailing", "Door Panel Cleaning", "Seat Deep Cleaning", "Floor Mat Cleaning", "Interior Plastic Dressing", "Interior Steam Cleaning", "AC Vent Cleaning", "Odour Removal Treatment", "Interior UV Protection", "Tyre Polish", "Exterior Glass Cleaning", "Final Quality Inspection"]'::jsonb, '{"subtitle": "Interior Deep Clean"}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('car_spa_signature_plus', 'Signature Spa+', 'SIGNATURE SPA+', 'Car Wash & Cleaning', array['car_spa']::text[], 'car', 'Complete restoration with paint treatment, engine bay detailing, and premium finishing.', 'Complete restoration with paint treatment, engine bay detailing, and premium finishing.', 2499, null, '150 mins', null, false, '["Premium Foam Wash", "Paint Decontamination", "Clay Bar Treatment", "Machine Wax Polish", "Paint Gloss Enhancement", "Exterior Plastic Restoration", "Wheel Arch Cleaning", "Alloy Wheel Detailing", "Tyre Dressing", "Complete Interior Vacuum", "Dashboard Restoration", "Leather / Fabric Seat Cleaning", "Carpet Shampooing", "Roof Lining Cleaning", "Door Panel Restoration", "Interior Steam Sanitization", "AC Vent Sanitization", "Engine Bay Cleaning", "Exterior Glass Treatment", "Premium Perfume Finish", "Final Quality Inspection"]'::jsonb, '{"subtitle": "Complete Car Restoration"}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('wheel_alignment', 'Wheel Alignment', 'WHEEL ALIGNMENT', 'Wheels & Tyres', array['wheel','tyre_care']::text[], 'car', 'Recommended if your vehicle pulls to one side.', 'Better handling, smoother driving, and longer tyre life', 499, null, '45 mins', null, false, '["Computerized alignment", "Steering correction", "Camber adjustment", "Wheel angle optimization", "Road stability testing"]'::jsonb, '{"best_for": "Every 8,000–10,000 km, after hitting potholes, or when the car pulls to one side.", "display": {"tyre_care": {"description": "Recommended if your vehicle pulls to one side or steering feels off-center.", "features": ["Computerized alignment", "Steering correction", "Camber adjustment", "Wheel angle optimization", "Road stability testing"], "featured": false, "has_extra_charge": false}}}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('wheel_balancing', 'Wheel Balancing', 'WHEEL BALANCING', 'Wheels & Tyres', array['wheel','tyre_care']::text[], 'car', 'Improves ride quality and tyre longevity.', 'Improves ride quality and tyre longevity', 299, null, '30 mins', null, false, '["Dynamic balancing", "Wheel weight calibration", "Vibration reduction", "High-speed balancing", "Extra charges up to ₹200 may apply (tyre-dependent)"]'::jsonb, '{"best_for": "Every 10,000 km, or if you feel vibration at highway speed.", "display": {"tyre_care": {"description": "Improves ride quality and tyre longevity through precise dynamic balancing.", "features": ["Dynamic balancing", "Wheel weight calibration", "Vibration reduction", "High-speed balancing"], "featured": false, "has_extra_charge": true}}}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('wheel_alignment_balancing', 'Wheel Alignment and Balancing', 'WHEEL ALIGNMENT AND BALANCING', 'Wheels & Tyres', array['wheel','tyre_care']::text[], 'car', 'Our most complete wheel care combo — alignment and balancing together.', 'Our most complete wheel care combo, in one visit', 799, null, '60 mins', 'Recommended', true, '["Everything in Wheel Alignment", "Dynamic balancing", "Wheel weight calibration", "Extra charges up to ₹200 may apply (tyre-dependent)"]'::jsonb, '{"best_for": "New tyres, high-speed vibration issues, or every 10,000 km.", "display": {"tyre_care": {"description": "Our most complete wheel care combo — precise computerized alignment and dynamic balancing together, in one visit.", "features": ["Computerized alignment", "Dynamic balancing", "Steering correction", "Wheel weight calibration", "Road stability testing"], "featured": true, "has_extra_charge": true}}}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('tyre_quick_air_check', 'Quick Air & Check', 'QUICK AIR & CHECK', 'Wheels & Tyres', array['tyre_care']::text[], 'car', 'Perfect for routine tyre maintenance.', 'Perfect for routine tyre maintenance and maximizing tyre life.', 299, null, '20 mins', null, false, '["Tyre pressure check", "Nitrogen refill", "Air leakage inspection", "Valve inspection", "Tread inspection"]'::jsonb, '{"featured": false, "has_extra_charge": false}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_shine', 'Paint Shine Package', 'PAINT SHINE PACKAGE', 'Paint & Body', array['paint_package']::text[], 'car', 'Restore gloss and protect your paint.', 'Restore gloss and protect your paint', 1999, null, '2-3 hrs', null, false, '["Premium Snow Foam Wash", "Surface Decontamination Wash", "Bug & Tar Removal", "Paint Gloss Enhancement Polish", "Machine Wax Application", "Exterior Plastic Trim Dressing", "Tyre Shine", "Exterior Glass Cleaning", "Paint Condition Inspection"]'::jsonb, '{"best_for": "Dull paint, light swirl marks, and maintaining your car''s shine.", "protection": "Up to 2–3 months"}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_protection', 'Paint Protection Package', 'PAINT PROTECTION PACKAGE', 'Paint & Body', array['paint_package']::text[], 'car', 'Long-lasting shine with enhanced paint protection.', 'Long-lasting shine with enhanced paint protection', 2999, null, '2-3 hrs', 'Recommended', true, '["Everything in Paint Shine Package", "One-Step Machine Paint Correction", "Ceramic Spray Coating", "Hydrophobic Water-Repellent Protection", "UV Protection for Paint", "Minor Scratch & Swirl Reduction", "Alloy Wheel Protection", "Exterior Plastic Restoration", "Rain-Repellent Glass Treatment", "Final Paint Gloss Inspection"]'::jsonb, '{"best_for": "Customers wanting better protection and an easier-to-clean finish.", "protection": "Up to 6 months"}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_addon_ceramic', 'Ceramic Coating', 'Ceramic Coating', 'Paint & Body', array['paint_package']::text[], 'car', 'Premium add-on upgrade.', 'Premium add-on upgrade.', 12999, null, 'Quoted on inspection', null, false, '["1–3 Year Paint Protection", "Deep Gloss Finish", "Hydrophobic Water Beading", "UV Protection", "Easier Cleaning", "Chemical Resistance"]'::jsonb, '{"price_prefix": "from", "addons_only_booking_name": "Paint Care Add-Ons"}'::jsonb, 30, true, true, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_addon_graphene', 'Graphene Coating', 'Graphene Coating', 'Paint & Body', array['paint_package']::text[], 'car', 'Premium add-on upgrade.', 'Premium add-on upgrade.', 16999, null, 'Quoted on inspection', null, false, '["Enhanced Ceramic Protection", "Better Heat Resistance", "Superior Gloss", "Water & Dirt Repellency", "Increased Durability"]'::jsonb, '{"price_prefix": "from", "addons_only_booking_name": "Paint Care Add-Ons"}'::jsonb, 40, true, true, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_addon_ppf', 'Paint Protection Film (PPF)', 'Paint Protection Film (PPF)', 'Paint & Body', array['paint_package']::text[], 'car', 'Premium add-on upgrade.', 'Premium add-on upgrade.', 49999, null, 'Quoted on inspection', null, false, '["Self-Healing Film", "Stone Chip Protection", "Scratch Resistance", "UV Protection", "High Gloss or Matte Finish", "Long-Term Paint Preservation"]'::jsonb, '{"price_prefix": "from", "addons_only_booking_name": "Paint Care Add-Ons"}'::jsonb, 50, true, true, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_addon_correction', 'Paint Correction', 'Paint Correction', 'Paint & Body', array['paint_package']::text[], 'car', 'Premium add-on upgrade.', 'Premium add-on upgrade.', 7999, null, 'Quoted on inspection', null, false, '["Multi-Stage Machine Polishing", "Removes Swirl Marks", "Removes Oxidation", "Restores Paint Clarity", "High Gloss Finish"]'::jsonb, '{"price_prefix": "from", "addons_only_booking_name": "Paint Care Add-Ons"}'::jsonb, 60, true, true, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_quick_polish', 'Quick Polish', 'QUICK POLISH', 'Paint & Body', array['paint_care']::text[], 'car', 'Perfect for restoring daily shine quickly.', 'Perfect for restoring daily shine and improving overall exterior appearance quickly.', 599, null, '45 mins', null, false, '["Exterior wash", "Quick buffing", "Tyre shine", "Water spot removal", "Gloss enhancement"]'::jsonb, '{"subtitle": "Basic Shine Enhancement"}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_scratch_control', 'Scratch Control', 'SCRATCH CONTROL', 'Paint & Body', array['paint_care']::text[], 'car', 'Removes minor scratches and swirl marks.', 'Designed to remove minor scratches, swirl marks and restore paint smoothness.', 1499, null, '2 hrs', null, false, '["Scratch removal", "Swirl correction", "Paint enhancement", "Machine buffing", "Gloss restoration"]'::jsonb, '{"subtitle": "Scratch & Swirl Correction"}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_rust_control', 'Rust Control', 'RUST CONTROL', 'Paint & Body', array['paint_care']::text[], 'car', 'Advanced anti-rust treatment protecting your vehicle body.', 'Advanced anti-rust treatment protecting your vehicle body from corrosion and damage.', 2999, null, '3 hrs', null, false, '["Underbody coating", "Rust treatment", "Corrosion prevention", "Protective sealant", "Metal protection layer"]'::jsonb, '{"subtitle": "Anti-Rust Protection"}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_premium_restore', 'Premium Paint Restore', 'PREMIUM PAINT RESTORE', 'Paint & Body', array['paint_care']::text[], 'car', 'Restores dull, oxidized, faded paint to a premium glossy finish.', 'Restores dull paint, oxidation and faded surfaces back to premium glossy finish.', 4999, null, '5 hrs', null, false, '["Paint correction", "Multi-stage polishing", "Deep gloss enhancement", "Oxidation removal", "Premium machine finish"]'::jsonb, '{"subtitle": "Paint Correction & Restoration"}'::jsonb, 40, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_vinyl_wrap_studio', 'Vinyl & Wrap Studio', 'VINYL & WRAP STUDIO', 'Paint & Body', array['paint_care']::text[], 'car', 'Premium wrapping for luxury styling and customization.', 'Premium wrapping solutions for luxury styling, customization and exterior transformation.', 7999, null, '1 day', null, false, '["Vinyl wrap installation", "Gloss/matte finish", "Roof wrap", "Mirror accents", "Color customization", "Paint-safe removal"]'::jsonb, '{"subtitle": "Exterior Customization"}'::jsonb, 50, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('paint_showroom_shine_plus', 'Showroom Shine+', 'SHOWROOM SHINE+', 'Paint & Body', array['paint_care']::text[], 'car', 'Showroom-level shine, protection and exterior perfection.', 'Ultimate luxury package delivering showroom-level shine, protection and exterior perfection.', 10999, null, '2 days', null, false, '["Ceramic coating", "Deep detailing", "Paint refinement", "Hydrophobic protection", "Luxury polishing", "Exterior rejuvenation", "PPF enhancement"]'::jsonb, '{"subtitle": "Luxury Exterior Restoration"}'::jsonb, 60, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_basic_inspection', 'Basic Inspection', 'BASIC INSPECTION', 'Paint & Body', array['denting']::text[], 'car', 'Professional inspection and repair consultation for dents & damage.', 'Professional inspection and repair consultation for dents, scratches, and accident damage.', 99, null, '20 mins', null, false, '["Dent inspection", "Paint damage check", "Panel alignment check", "Repair estimate", "Insurance guidance"]'::jsonb, '{"subtitle": "Damage Assessment & Estimate"}'::jsonb, 10, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_quick_fix', 'Quick Dent Fix', 'QUICK DENT FIX', 'Paint & Body', array['denting']::text[], 'car', 'Perfect for small dents and scratches from daily driving.', 'Perfect for small dents and scratches caused by daily driving and parking incidents.', 1499, null, '2 hrs', null, false, '["Minor dent removal", "Scratch correction", "Panel finishing", "Basic touch-up", "FREE inspection", "FREE polish"]'::jsonb, '{"subtitle": "Minor Dent & Scratch Repair"}'::jsonb, 20, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_panel_restore', 'Panel Restore', 'PANEL RESTORE', 'Paint & Body', array['denting']::text[], 'car', 'Restores damaged doors, bumpers, and side panels.', 'Advanced restoration package focused on restoring damaged doors, bumpers, and side panels.', 3999, null, '5 hrs', null, false, '["Deep dent repair", "Paint blending", "Panel reshaping", "Machine polishing", "FREE inspection", "FREE polish"]'::jsonb, '{"subtitle": "Single Panel Restoration"}'::jsonb, 30, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_body_line_correction', 'Body Line Correction', 'BODY LINE CORRECTION', 'Paint & Body', array['denting']::text[], 'car', 'Restores factory body lines and alignment.', 'Premium body correction service for restoring factory body lines and alignment.', 4999, null, '6 hrs', null, false, '["Multi-panel correction", "Bumper alignment", "Precision reshaping", "Machine finishing", "Paint refinement", "FREE inspection", "FREE polish"]'::jsonb, '{"subtitle": "Multi-Panel Alignment"}'::jsonb, 40, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_accident_restoration', 'Accident Restoration', 'ACCIDENT RESTORATION', 'Paint & Body', array['denting']::text[], 'car', 'Comprehensive accident repair for heavily damaged vehicles.', 'Comprehensive accident repair package for heavily damaged vehicles requiring structural correction.', 7999, null, '1 day', null, false, '["Structural correction", "Deep restoration", "Paint correction", "Body alignment", "Insurance assistance", "FREE inspection", "FREE polish"]'::jsonb, '{"subtitle": "Major Damage Recovery"}'::jsonb, 50, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('dent_signature_restoration_plus', 'Signature Restoration+', 'SIGNATURE RESTORATION+', 'Paint & Body', array['denting']::text[], 'car', 'Showroom-level restoration with luxury finishing.', 'Ultimate showroom-level restoration package with luxury finishing and advanced detailing.', 10999, null, '2 days', null, false, '["Complete body rejuvenation", "Luxury paint finishing", "Advanced paint refinement", "Ceramic finishing", "Premium detailing", "Insurance support", "FREE inspection", "FREE polish"]'::jsonb, '{"subtitle": "Luxury Finish Restoration"}'::jsonb, 60, true, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('detail_ppf_premium', 'PPF Premium', 'PPF Premium', 'Premium Detailing', array['detailing']::text[], 'car', 'Ultimate protection against scratches, chips & UV.', 'Ultimate protection against scratches, chips & UV.', 55000, null, 'New car — 3 days', null, false, '["400 sq ft base coverage", "₹400/sq ft", "Warranty: 3 to 5 Years", "3-Day turnaround for new cars"]'::jsonb, '{"coverage": "400 sq ft base", "warranty": "3-5 Years", "turnaround": "3 Days (New)", "price_per_sq_ft": "₹400/sq ft", "group": "ppf", "brand": "PPF Premium", "premium": false}'::jsonb, 10, true, false, false, null, false, 'optional', true, null, null, null),
  ('detail_ppf_full', 'PPF - Full Coverage', 'PPF - Full Coverage', 'Premium Detailing', array['detailing']::text[], 'car', 'Premium-grade film for maximum protection — choose your preferred brand.', 'Premium-grade film for maximum protection — choose your preferred brand.', null, '₹75,000 - ₹1,00,000', 'Used car — 5 days', null, true, '["Full Coverage", "Warranty: 8 Years", "5-Day turnaround (includes polish for used cars)"]'::jsonb, '{"coverage": "Full Coverage", "warranty": "8 Years", "turnaround": "5 Days (Used)", "price_per_sq_ft": "Premium Pricing", "group": "ppf", "brand": "PPF - Full Coverage", "premium": true}'::jsonb, 20, true, false, false, null, false, 'optional', true, null, null, null),
  ('detail_ceramic', 'Ceramic Coating (Detailing Studio)', 'Ceramic Coating', 'Premium Detailing', array['detailing']::text[], 'car', 'Hydrophobic protection with stunning gloss.', 'Hydrophobic protection with stunning gloss.', 16000, null, '2 days', null, false, '["Full Vehicle Coverage", "1-Year Warranty", "Water beading effect", "Enhanced glossiness", "Easy maintenance"]'::jsonb, '{"coverage": "Full Vehicle", "warranty": "1 Year", "turnaround": "2 Days", "feature": "Glossy Finish", "group": "ceramic", "brand": "Ceramic Coating", "premium": false}'::jsonb, 30, true, false, false, null, false, 'optional', true, null, null, null),
  ('detail_graphene', 'Graphene Coating (Detailing Studio)', 'Graphene Coating', 'Premium Detailing', array['detailing']::text[], 'car', 'Next-gen protection with nano-technology.', 'Next-gen protection with nano-technology.', 22000, null, '2 days', null, false, '["Full Vehicle Coverage", "3-Year Warranty", "Graphene nano-particles", "Superior durability", "Self-cleaning properties", "UV protection included"]'::jsonb, '{"coverage": "Full Vehicle", "warranty": "3 Years", "turnaround": "2 Days", "feature": "Advanced Protection", "group": "graphene", "brand": "Graphene Coating", "premium": true}'::jsonb, 40, true, false, false, null, false, 'optional', true, null, null, null),
  ('detail_sunfilm_standard', 'Sun Film - Standard', 'Sun Film - Standard', 'Premium Detailing', array['detailing']::text[], 'car', 'Beat the heat with premium UV blocking.', 'Beat the heat with premium UV blocking.', null, '₹20,000 - ₹45,000', '2 days', null, false, '["5-Year Warranty", "Front only — ₹8,000", "Sides only — ₹8,000", "Front + Sides — ₹15,000", "Full Coverage — ₹20,000+"]'::jsonb, '{"coverage": "Variable", "warranty": "5 Years", "turnaround": "2 Days", "feature": "Heat Rejection", "coverage_options": [{"area": "Front", "price": "₹8,000"}, {"area": "Sides", "price": "₹8,000"}, {"area": "Front + Sides", "price": "₹15,000"}, {"area": "Full Coverage", "price": "₹20,000+"}], "group": "sun_film", "brand": "Sun Film - Standard", "premium": false}'::jsonb, 50, true, false, false, null, false, 'optional', true, null, null, null),
  ('detail_sunfilm_premium', 'Sun Film - Premium', 'Sun Film - Premium', 'Premium Detailing', array['detailing']::text[], 'car', 'Top-tier heat rejection film, full body — choose your preferred brand.', 'Top-tier heat rejection film, full body — choose your preferred brand.', 25000, null, '2 days', null, false, '["Full Body Coverage", "Warranty: 5 to 10 Years", "Maximum heat & UV protection"]'::jsonb, '{"coverage": "Full Body", "warranty": "5-10 Years", "turnaround": "2 Days", "feature": "Maximum Protection", "group": "sun_film", "brand": "Sun Film - Premium", "premium": true}'::jsonb, 60, true, false, false, null, false, 'optional', true, null, null, null),
  ('bike_service_125', 'General Bike Service (Up to 125 CC)', 'General Bike Service (Up to 125 CC)', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Complete general service for your bike.', 'Up to 125 CC', 799, null, '1-2 hrs', null, false, '["Complete vehicle general inspection", "Air filter inspection", "Brake inspection", "Tyre pressure and condition check", "Battery and electrical check", "Chain cleaning, lubrication and adjustment (chain-drive bikes)", "Clutch and throttle check", "Suspension and steering inspection", "Visible nuts, bolts and cable check", "Check for visible leaks and unusual noises", "Basic vehicle cleaning", "Final inspection after servicing"]'::jsonb, '{"engine_label": "Up to 125 CC"}'::jsonb, 10, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_service_200', 'General Bike Service (126–200 CC)', 'General Bike Service (126–200 CC)', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Complete general service for your bike.', '126–200 CC', 999, null, '1-2 hrs', null, false, '["Complete vehicle general inspection", "Air filter inspection", "Brake inspection", "Tyre pressure and condition check", "Battery and electrical check", "Chain cleaning, lubrication and adjustment (chain-drive bikes)", "Clutch and throttle check", "Suspension and steering inspection", "Visible nuts, bolts and cable check", "Check for visible leaks and unusual noises", "Basic vehicle cleaning", "Final inspection after servicing"]'::jsonb, '{"engine_label": "126–200 CC"}'::jsonb, 20, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_service_350', 'General Bike Service (201–350 CC)', 'General Bike Service (201–350 CC)', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Complete general service for your bike.', '201–350 CC', 1499, null, '1-2 hrs', null, false, '["Complete vehicle general inspection", "Air filter inspection", "Brake inspection", "Tyre pressure and condition check", "Battery and electrical check", "Chain cleaning, lubrication and adjustment (chain-drive bikes)", "Clutch and throttle check", "Suspension and steering inspection", "Visible nuts, bolts and cable check", "Check for visible leaks and unusual noises", "Basic vehicle cleaning", "Final inspection after servicing"]'::jsonb, '{"engine_label": "201–350 CC"}'::jsonb, 30, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_service_500', 'General Bike Service (351–500 CC)', 'General Bike Service (351–500 CC)', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Complete general service for your bike.', '351–500 CC', 2999, null, '1-2 hrs', null, false, '["Complete vehicle general inspection", "Air filter inspection", "Brake inspection", "Tyre pressure and condition check", "Battery and electrical check", "Chain cleaning, lubrication and adjustment (chain-drive bikes)", "Clutch and throttle check", "Suspension and steering inspection", "Visible nuts, bolts and cable check", "Check for visible leaks and unusual noises", "Basic vehicle cleaning", "Final inspection after servicing"]'::jsonb, '{"engine_label": "351–500 CC"}'::jsonb, 40, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_service_501_plus', 'General Bike Service (501 CC & Above)', 'General Bike Service (501 CC & Above)', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Complete general service for your bike.', '501 CC & Above', 3999, null, '1-2 hrs', null, false, '["Complete vehicle general inspection", "Air filter inspection", "Brake inspection", "Tyre pressure and condition check", "Battery and electrical check", "Chain cleaning, lubrication and adjustment (chain-drive bikes)", "Clutch and throttle check", "Suspension and steering inspection", "Visible nuts, bolts and cable check", "Check for visible leaks and unusual noises", "Basic vehicle cleaning", "Final inspection after servicing"]'::jsonb, '{"engine_label": "501 CC & Above"}'::jsonb, 50, false, false, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_oil_change_addon', 'Oil Change Add-on', 'Oil Change Add-on', 'Two-Wheeler Care', array['bike_servicing']::text[], 'bike', 'Engine oil, air filter and oil filter replacement.', null, 400, null, '', null, false, '["Engine oil change", "Air filter change", "Oil filter change"]'::jsonb, '{"booking_suffix": " + Oil Change Add-on"}'::jsonb, 60, false, true, true, 'bookings', true, 'optional', true, 'garage_{vehicle}', 'delivery_main', null),
  ('bike_wash_quick', 'Quick Wash', 'QUICK WASH', 'Two-Wheeler Care', array['bike_washing']::text[], 'bike', 'Everyday clean', 'Everyday clean', 149, null, '30-45 mins', null, false, '["Foam Wash", "Pressure Rinse", "Hand Wash", "Tyre & Rim Clean", "Microfiber Dry"]'::jsonb, '{}'::jsonb, 10, false, false, true, 'bookings', true, 'none', true, null, null, 'washers_main'),
  ('bike_wash_premium', 'Premium Wash', 'PREMIUM WASH', 'Two-Wheeler Care', array['bike_washing']::text[], 'bike', 'Deep clean & shine', 'Deep clean & shine', 299, null, '30-45 mins', 'Most Popular', true, '["Premium Foam", "Deep Rim Clean", "Chain Clean & Lube", "Tyre Dressing", "Plastic Polish", "Microfiber Finish"]'::jsonb, '{}'::jsonb, 20, false, false, true, 'bookings', true, 'none', true, null, null, 'washers_main'),
  ('pollution_check', 'Pollution Certificate Check', 'Pollution Certificate Check', 'Compliance', array['pollution']::text[], 'any', 'Doorstep pickup & drop for your PUC certificate.', null, 299, null, 'Same day', null, false, '[]'::jsonb, '{}'::jsonb, 10, false, false, true, 'pollution_booking', true, 'included', true, null, 'delivery_dedicated', null),
  ('inspection_suv', 'Vehicle Health Check (SUV)', 'Vehicle Health Check', 'Compliance', array['inspection']::text[], 'any', 'Complete pre-purchase / health inspection with a digital report.', null, 1599, null, 'Quick turnaround', null, false, '[]'::jsonb, '{"vehicle_type_label": "SUV"}'::jsonb, 10, false, false, true, 'inspection_booking', true, 'included', true, null, 'delivery_dedicated', null),
  ('inspection_hatchback', 'Vehicle Health Check (Hatchback)', 'Vehicle Health Check', 'Compliance', array['inspection']::text[], 'any', 'Complete pre-purchase / health inspection with a digital report.', null, 1299, null, 'Quick turnaround', null, false, '[]'::jsonb, '{"vehicle_type_label": "Hatchback"}'::jsonb, 20, false, false, true, 'inspection_booking', true, 'included', true, null, 'delivery_dedicated', null),
  ('inspection_ev', 'Vehicle Health Check (EV)', 'Vehicle Health Check', 'Compliance', array['inspection']::text[], 'any', 'Complete pre-purchase / health inspection with a digital report.', null, 1999, null, 'Quick turnaround', null, false, '[]'::jsonb, '{"vehicle_type_label": "EV"}'::jsonb, 30, false, false, true, 'inspection_booking', true, 'included', true, null, 'delivery_dedicated', null),
  ('inspection_luxury', 'Vehicle Health Check (Luxury)', 'Vehicle Health Check', 'Compliance', array['inspection']::text[], 'any', 'Complete pre-purchase / health inspection with a digital report.', null, 3999, null, 'Quick turnaround', null, false, '[]'::jsonb, '{"vehicle_type_label": "Luxury"}'::jsonb, 40, false, false, true, 'inspection_booking', true, 'included', true, null, 'delivery_dedicated', null),
  ('claim_assistance', 'Claim Assistance Service', 'Claim Assistance Service', 'Claim Assistance', array['claim']::text[], 'any', 'Cashless accident assistance — we handle the paperwork with your insurer.', 'Doorstep pickup & drop', 3999, null, 'Doorstep pickup & drop', null, false, '["Cashless claim assistance", "Document pickup & digital submission", "Approved garage network", "End-to-end claim status tracking"]'::jsonb, '{}'::jsonb, 10, true, false, true, 'claim_table', true, 'included', false, 'garage_claims', 'delivery_dedicated', null),
  ('monthly_wash_hatchback', 'Monthly Wash Plan - Hatchback / Small Cars', 'Monthly Wash Plan - Hatchback / Small Cars', 'Monthly Wash', array['monthly_wash']::text[], 'car', 'Daily doorstep car wash for 30 days — price depends on your vehicle type.', 'Hatchback / Small Cars', 699, null, '1 Month', null, false, '["6 Water Washes / Week", "2 Interior Washes / Week", "Daily App Updates", "Free Shampoo Wash on missed days", "Flexible Timings (4 AM-9 AM, except Wednesdays)", "No Contact Required"]'::jsonb, '{"plan_type": "hatchback", "plan_label": "Hatchback / Small Cars", "vehicles": "Maruti Alto K10, Hyundai i20, Tata Punch, etc", "duration_days": 30, "price_suffix": "/month"}'::jsonb, 10, true, false, true, 'monthlywash_table', true, 'none', true, null, null, 'washers_subscriptions'),
  ('monthly_wash_suv', 'Monthly Wash Plan - SUV / XUV / SEDAN', 'Monthly Wash Plan - SUV / XUV / SEDAN', 'Monthly Wash', array['monthly_wash']::text[], 'car', 'Daily doorstep car wash for 30 days — price depends on your vehicle type.', 'SUV / XUV / SEDAN', 1099, null, '1 Month', null, false, '["6 Water Washes / Week", "2 Interior Washes / Week", "Daily App Updates", "Free Shampoo Wash on missed days", "Flexible Timings (4 AM-9 AM, except Wednesdays)", "No Contact Required"]'::jsonb, '{"plan_type": "suv", "plan_label": "SUV / XUV / SEDAN", "vehicles": "Mahindra XUV500, Hyundai Creta, Tata Nexon, etc", "duration_days": 30, "price_suffix": "/month"}'::jsonb, 20, true, false, true, 'monthlywash_table', true, 'none', true, null, null, 'washers_subscriptions'),
  ('monthly_wash_luxury', 'Monthly Wash Plan - Luxury Cars', 'Monthly Wash Plan - Luxury Cars', 'Monthly Wash', array['monthly_wash']::text[], 'car', 'Daily doorstep car wash for 30 days — price depends on your vehicle type.', 'Luxury Cars', 1999, null, '1 Month', null, false, '["6 Water Washes / Week", "2 Interior Washes / Week", "Daily App Updates", "Free Shampoo Wash on missed days", "Flexible Timings (4 AM-9 AM, except Wednesdays)", "No Contact Required"]'::jsonb, '{"plan_type": "luxury", "plan_label": "Luxury Cars", "vehicles": "Audi, BMW, Mercedes-Benz, etc", "duration_days": 30, "price_suffix": "/month"}'::jsonb, 30, true, false, true, 'monthlywash_table', true, 'none', true, null, null, 'washers_subscriptions'),
  ('monthly_wash_bike', 'Monthly Wash Plan - Bike', 'Monthly Wash Plan - Bike', 'Monthly Wash', array['monthly_wash']::text[], 'bike', 'Daily doorstep car wash for 30 days — price depends on your vehicle type.', 'Bike', 499, null, '1 Month', null, false, '["6 Water Washes / Week", "2 Interior Washes / Week", "Daily App Updates", "Free Shampoo Wash on missed days", "Flexible Timings (4 AM-9 AM, except Wednesdays)", "No Contact Required"]'::jsonb, '{"plan_type": "bike", "plan_label": "Bike", "vehicles": "All bikes & scooters", "duration_days": 30, "price_suffix": "/month"}'::jsonb, 40, true, false, true, 'monthlywash_table', true, 'none', true, null, null, 'washers_subscriptions'),
  ('roadside_assistance', 'Roadside Assistance', 'Roadside Assistance', 'Roadside Assistance', array['roadside']::text[], 'any', 'Emergency roadside help, wherever you are — extra charges may apply based on distance.', null, 399, null, 'On-demand', null, false, '["Flat Tyre change", "Dead Battery jumpstart", "Out-of-Fuel delivery", "Towing assistance", "Breakdown support", "Accident support"]'::jsonb, '{"booking_label_format": "Roadside Assistance - {label}"}'::jsonb, 10, true, false, true, 'bookings', false, 'locked', true, 'garage_emergency', null, null),
  ('fleet_management', 'Fleet Management', 'Fleet Management', 'Business Solutions', array['fleet_management']::text[], 'any', 'End-to-end fleet servicing for businesses with multiple vehicles.', null, null, 'Custom Quote', null, null, false, '["Dedicated account manager", "Priority scheduling", "Consolidated billing", "Multi-vehicle tracking"]'::jsonb, '{}'::jsonb, 10, true, false, false, null, false, 'optional', true, null, null, null),
  ('battery_management', 'Battery Management', 'Battery Management', 'Business Solutions', array['fleet_management']::text[], 'any', 'EV & conventional battery care.', null, null, null, null, null, false, '[]'::jsonb, '{}'::jsonb, 20, true, false, false, null, false, 'optional', true, null, null, null),
  ('partner_garage_program', 'Partner Garage Program', 'Partner Garage Program', 'Business Solutions', array['fleet_management']::text[], 'any', 'Join our garage network.', null, null, null, null, null, false, '[]'::jsonb, '{}'::jsonb, 30, true, false, false, null, false, 'optional', true, null, null, null)
on conflict (key) do nothing;
