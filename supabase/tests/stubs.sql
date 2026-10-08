-- Test-only stand-ins for the existing Reperi tables (just the columns the
-- booking code touches) plus sample admins / partners / washers.
-- Minimal stand-ins for the existing Reperi tables (columns the code uses)
create role anon; create role authenticated; create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create table public.admin (id uuid primary key default gen_random_uuid(), username text, vehicle text);
create table public.delivery_partners (id serial primary key, email text);
create table public.washers (id serial primary key, email text);
create table public.vehicles (id uuid primary key default gen_random_uuid(), user_id uuid, vehicle_type text, car_brand text, car_model text, car_number text);
create table public.profiles (id uuid primary key, name text, email text, phone text, active_vehicle_id uuid);
create table public.user_addresses (id serial primary key, user_id uuid, name text, address text, latitude float8, longitude float8, is_default bool, created_at timestamptz default now());
create table public.bookings (id serial primary key, user_id uuid, vehicle_id uuid, package_name text, package_price text, pickupdrop text,
  delivery_partner_id int, washer_id int, razorpay_order_id text, razorpay_payment_id text, payment_status text,
  pickup_address text, pickup_latitude float8, pickup_longitude float8, pickup_address_name text,
  dropoff_address text, dropoff_latitude float8, dropoff_longitude float8, dropoff_address_name text,
  customer_name text, customer_phone text, assigned_to_admin_id uuid, booking_status text, has_unread_update bool default false, created_at timestamptz default now());
create table public.pollution_booking (id serial primary key, user_id uuid, vehicle_id uuid, price text, razorpay_order_id text, razorpay_payment_id text,
  pickup_address text, pickup_latitude float8, pickup_longitude float8, pickup_address_name text, dropoff_address text, dropoff_latitude float8, dropoff_longitude float8, dropoff_address_name text,
  delivery_partner_id int, pickupdrop text, status text, customer_name text, customer_phone text);
create table public.inspection_booking (id serial primary key, user_id uuid, vehicle_id uuid, razorpay_order_id text, razorpay_payment_id text,
  pickup_address text, pickup_latitude float8, pickup_longitude float8, pickup_address_name text, dropoff_address text, dropoff_latitude float8, dropoff_longitude float8, dropoff_address_name text,
  delivery_partner_id int, pickupdrop text, status text, vehicle_condition text, vehicle_type text, package_price text, slot_date date, slot_time text, customer_name text, customer_phone text);
create table public.claim_table (id serial primary key, user_id uuid, vehicle_id uuid, assigned_to_admin_id uuid, claim_status text, damage_description text,
  rc_copy_url text, driving_license_url text, owner_aadhaar_url text, owner_pan_url text, insurance_copy_url text, damage_photo_url text, has_unread_update bool, created_at timestamptz,
  delivery_partner_id int, pickupdrop text, pickup_address text, pickup_latitude float8, pickup_longitude float8, pickup_address_name text, dropoff_address text, dropoff_latitude float8, dropoff_longitude float8, dropoff_address_name text,
  package_price text, payment_status text, razorpay_order_id text, razorpay_payment_id text, customer_name text, customer_phone text);
create table public.monthlywash_table (id serial primary key, user_id uuid, vehicle_id uuid, plan_type text, plan_title text, price numeric, status text, start_date timestamptz, end_date timestamptz,
  payment_id text, order_id text, pickup_address text, pickup_latitude float8, pickup_longitude float8, pickup_address_name text, washer_id int);
create table public.fleet_pickup_requests (id serial primary key, fleet_user_id text, company_name text, username text, total_amount numeric, bill_items jsonb, payment_status text, razorpay_order_id text, razorpay_payment_id text, status text);
-- realistic data
insert into public.admin (id, username, vehicle) values
 ('11111111-0000-0000-0000-000000000001','haya_autogears','four wheeler'),
 ('11111111-0000-0000-0000-000000000002','garage_b','four wheeler'),
 ('11111111-0000-0000-0000-000000000003','bike_garage','two wheeler'),
 ('11111111-0000-0000-0000-000000000004','emergency_service',null),
 ('1bcf9d81-6625-4c01-ac23-f0c237462eb7','newexpert_care',null),
 ('11111111-0000-0000-0000-000000000006','appreview@gmail.com','four wheeler');
insert into public.delivery_partners (email) values ('d1@x.com'),('d2@x.com'),('d3@x.com'),('delivery_apple@gmail.com');
insert into public.washers (email) values ('w1@x.com'),('w2@x.com'),('washer_apple@gmail.com');
insert into public.bookings (assigned_to_admin_id, washer_id) values
 ('11111111-0000-0000-0000-000000000001',null),('11111111-0000-0000-0000-000000000001',null),('11111111-0000-0000-0000-000000000002',null),
 ('11111111-0000-0000-0000-000000000003',null),(null,1),(null,2),(null,1);
