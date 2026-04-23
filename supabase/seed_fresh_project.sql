-- NightBites: paste this entire file into the Supabase SQL Editor (one run).
-- For an empty / new project. Safe to re-run in parts; uses IF NOT EXISTS / DROP IF EXISTS where needed.

-- ---------------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------------

create table if not exists public.campuses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  latitude double precision not null,
  longitude double precision not null
);

create table if not exists public.food_trucks (
  id uuid primary key default gen_random_uuid(),
  owner_user_id text,
  name text not null,
  cuisine_type text not null,
  campus_name text not null,
  latitude double precision not null,
  longitude double precision not null,
  plan text not null default 'free',
  distance double precision,
  rating double precision,
  rating_count integer,
  estimated_wait integer default 15,
  is_open boolean default true,
  orders_paused boolean default false,
  closed_early boolean default false,
  active_hours text default 'Not set',
  image_name text,
  cover_image_url text,
  profile_image_url text,
  gallery_image_urls text[],
  live_latitude double precision,
  live_longitude double precision,
  has_live_tracking boolean,
  pro_subscription_active boolean,
  closing_at timestamptz
);

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  truck_id text not null,
  truck_name text not null,
  name text not null,
  description text not null,
  price double precision not null,
  category text not null,
  is_available boolean not null default true,
  image_url text,
  tags text[] default '{}'::text[],
  modifier_groups jsonb not null default '[]'::jsonb
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  truck_id text,
  customer_user_id text,
  truck_name text not null,
  campus_name text not null,
  customer_name text not null default 'Guest',
  subtotal_amount double precision not null default 0,
  service_fee_amount double precision not null default 0,
  charged_total_amount double precision not null default 0,
  total_amount double precision not null,
  status text not null,
  payment_method text not null,
  payment_status text not null default 'Pay on Pickup',
  payment_transaction_id text,
  pickup_timing text not null default 'ASAP',
  order_date timestamptz not null,
  estimated_delivery timestamptz,
  special_instructions text,
  items jsonb not null default '[]'::jsonb
);

create table if not exists public.truck_applications (
  id uuid primary key default gen_random_uuid(),
  truck_name text not null,
  owner_name text not null,
  cuisine_type text not null,
  campus_name text not null,
  contact_email text not null,
  selected_plan text not null,
  created_at timestamptz not null,
  status text not null
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  truck_id text not null,
  user_display_name text not null,
  rating integer not null,
  text text not null,
  media_url text,
  created_at timestamptz not null
);

create table if not exists public.profiles (
  user_id text primary key,
  role text not null check (role in ('student', 'owner'))
);

-- ---------------------------------------------------------------------------
-- 2) Auth: profile on signup
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using ((auth.uid())::text = user_id);

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, role)
  values (
    new.id::text,
    coalesce(new.raw_user_meta_data ->> 'role', 'student')
  )
  on conflict (user_id) do update
  set role = excluded.role;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

-- ---------------------------------------------------------------------------
-- 3) RLS on app tables
-- ---------------------------------------------------------------------------

alter table public.campuses enable row level security;
alter table public.food_trucks enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;
alter table public.truck_applications enable row level security;
alter table public.reviews enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.campuses to anon, authenticated;
grant select on public.food_trucks to anon, authenticated;
grant select on public.menu_items to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant select, insert, update on public.orders to authenticated;
grant select, insert, update on public.food_trucks to authenticated;
grant select, insert, update on public.menu_items to authenticated;
grant insert on public.truck_applications to authenticated;
grant insert on public.reviews to authenticated;
grant select on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Helper functions and policies
-- ---------------------------------------------------------------------------

create or replace function public.current_user_role()
returns text
language sql
stable
as $$
  select role
  from public.profiles
  where user_id = auth.uid()::text
  limit 1
$$;

create or replace function public.is_owner_of_truck(target_truck_id text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.food_trucks
    where id::text = target_truck_id
      and owner_user_id = auth.uid()::text
  )
$$;

drop policy if exists "campuses_public_read" on public.campuses;
create policy "campuses_public_read"
on public.campuses
for select
to anon, authenticated
using (true);

drop policy if exists "food_trucks_public_read" on public.food_trucks;
create policy "food_trucks_public_read"
on public.food_trucks
for select
to anon, authenticated
using (true);

drop policy if exists "food_trucks_owner_insert" on public.food_trucks;
create policy "food_trucks_owner_insert"
on public.food_trucks
for insert
to authenticated
with check (
  public.current_user_role() = 'owner'
  and owner_user_id = auth.uid()::text
);

drop policy if exists "food_trucks_owner_update" on public.food_trucks;
create policy "food_trucks_owner_update"
on public.food_trucks
for update
to authenticated
using (owner_user_id = auth.uid()::text)
with check (owner_user_id = auth.uid()::text);

drop policy if exists "menu_items_public_read" on public.menu_items;
create policy "menu_items_public_read"
on public.menu_items
for select
to anon, authenticated
using (true);

drop policy if exists "menu_items_owner_insert" on public.menu_items;
create policy "menu_items_owner_insert"
on public.menu_items
for insert
to authenticated
with check (
  public.current_user_role() = 'owner'
  and public.is_owner_of_truck(truck_id)
);

drop policy if exists "menu_items_owner_update" on public.menu_items;
create policy "menu_items_owner_update"
on public.menu_items
for update
to authenticated
using (public.is_owner_of_truck(truck_id))
with check (public.is_owner_of_truck(truck_id));

drop policy if exists "orders_student_read_own" on public.orders;
create policy "orders_student_read_own"
on public.orders
for select
to authenticated
using (
  customer_user_id = auth.uid()::text
  or public.is_owner_of_truck(truck_id)
);

drop policy if exists "orders_student_insert_own" on public.orders;
create policy "orders_student_insert_own"
on public.orders
for insert
to authenticated
with check (
  customer_user_id = auth.uid()::text
);

drop policy if exists "orders_owner_update_owned_truck" on public.orders;
create policy "orders_owner_update_owned_truck"
on public.orders
for update
to authenticated
using (public.is_owner_of_truck(truck_id))
with check (public.is_owner_of_truck(truck_id));

drop policy if exists "truck_applications_owner_insert" on public.truck_applications;
create policy "truck_applications_owner_insert"
on public.truck_applications
for insert
to authenticated
with check (public.current_user_role() = 'owner');

drop policy if exists "reviews_public_read" on public.reviews;
create policy "reviews_public_read"
on public.reviews
for select
to anon, authenticated
using (true);

drop policy if exists "reviews_authenticated_insert" on public.reviews;
create policy "reviews_authenticated_insert"
on public.reviews
for insert
to authenticated
with check (true);

-- ---------------------------------------------------------------------------
-- 5) Storage: menu item photos
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'menu-assets',
  'menu-assets',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Menu assets are publicly readable" on storage.objects;
create policy "Menu assets are publicly readable"
on storage.objects
for select
to public
using (bucket_id = 'menu-assets');

drop policy if exists "Authenticated users can upload menu assets" on storage.objects;
create policy "Authenticated users can upload menu assets"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'menu-assets');

drop policy if exists "Authenticated users can update their menu assets" on storage.objects;
create policy "Authenticated users can update their menu assets"
on storage.objects
for update
to authenticated
using (bucket_id = 'menu-assets')
with check (bucket_id = 'menu-assets');

drop policy if exists "Authenticated users can delete menu assets" on storage.objects;
create policy "Authenticated users can delete menu assets"
on storage.objects
for delete
to authenticated
using (bucket_id = 'menu-assets');

-- ---------------------------------------------------------------------------
-- 6) Sample campuses (app needs at least one)
-- ---------------------------------------------------------------------------

insert into public.campuses (name, latitude, longitude)
values
  ('UCLA', 34.0689, -118.4452),
  ('USC', 34.0211, -118.2870),
  ('UC Berkeley', 37.8719, -122.2585)
on conflict (name) do nothing;
