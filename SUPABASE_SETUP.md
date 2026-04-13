# Supabase Setup (NightBites)

Add these keys in your iOS target Info settings:
- `SUPABASE_URL` = `https://<project-ref>.supabase.co`
- `SUPABASE_ANON_KEY` = `<anon-key>`

## Tables expected by app

```sql
create table if not exists campuses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  latitude double precision not null,
  longitude double precision not null
);

create table if not exists food_trucks (
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

create table if not exists menu_items (
  id uuid primary key default gen_random_uuid(),
  truck_id text not null,
  truck_name text not null,
  name text not null,
  description text not null,
  price double precision not null,
  category text not null,
  is_available boolean not null default true,
  image_url text,
  tags text[] default '{}'::text[]
);

create table if not exists orders (
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

create table if not exists truck_applications (
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

create table if not exists reviews (
  id uuid primary key default gen_random_uuid(),
  truck_id text not null,
  user_display_name text not null,
  rating integer not null,
  text text not null,
  media_url text,
  created_at timestamptz not null
);

create table if not exists profiles (
  user_id text primary key,
  role text not null check (role in ('student', 'owner'))
);

alter table profiles enable row level security;

create policy "profiles_select_own"
on profiles
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
```

## Order pricing migration

The app now expects orders to store:

- `subtotal_amount`
- `service_fee_amount`
- `charged_total_amount`
- `payment_status`
- `payment_transaction_id`

If your `orders` table already exists, run:

```sql
\i supabase/migrations/20260224_add_order_payment_columns.sql
```

Or paste the contents of:

- [20260224_add_order_payment_columns.sql](/Users/kylerhu/NightBites/supabase/migrations/20260224_add_order_payment_columns.sql)

## Recommended RLS policies for pilot launch

Run this after the tables exist. It keeps browsing public while restricting private order and owner actions to authenticated users.

```sql
alter table campuses enable row level security;
alter table food_trucks enable row level security;
alter table menu_items enable row level security;
alter table orders enable row level security;
alter table truck_applications enable row level security;
alter table reviews enable row level security;

grant usage on schema public to anon, authenticated;
grant select on campuses to anon, authenticated;
grant select on food_trucks to anon, authenticated;
grant select on menu_items to anon, authenticated;
grant select on reviews to anon, authenticated;
grant select, insert, update on orders to authenticated;
grant select, insert, update on food_trucks to authenticated;
grant select, insert, update on menu_items to authenticated;
grant insert on truck_applications to authenticated;
grant insert on reviews to authenticated;
grant select on profiles to authenticated;

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

drop policy if exists "campuses_public_read" on campuses;
create policy "campuses_public_read"
on campuses
for select
to anon, authenticated
using (true);

drop policy if exists "food_trucks_public_read" on food_trucks;
create policy "food_trucks_public_read"
on food_trucks
for select
to anon, authenticated
using (true);

drop policy if exists "food_trucks_owner_insert" on food_trucks;
create policy "food_trucks_owner_insert"
on food_trucks
for insert
to authenticated
with check (
  public.current_user_role() = 'owner'
  and owner_user_id = auth.uid()::text
);

drop policy if exists "food_trucks_owner_update" on food_trucks;
create policy "food_trucks_owner_update"
on food_trucks
for update
to authenticated
using (owner_user_id = auth.uid()::text)
with check (owner_user_id = auth.uid()::text);

drop policy if exists "menu_items_public_read" on menu_items;
create policy "menu_items_public_read"
on menu_items
for select
to anon, authenticated
using (true);

drop policy if exists "menu_items_owner_insert" on menu_items;
create policy "menu_items_owner_insert"
on menu_items
for insert
to authenticated
with check (
  public.current_user_role() = 'owner'
  and public.is_owner_of_truck(truck_id)
);

drop policy if exists "menu_items_owner_update" on menu_items;
create policy "menu_items_owner_update"
on menu_items
for update
to authenticated
using (public.is_owner_of_truck(truck_id))
with check (public.is_owner_of_truck(truck_id));

drop policy if exists "orders_student_read_own" on orders;
create policy "orders_student_read_own"
on orders
for select
to authenticated
using (
  customer_user_id = auth.uid()::text
  or public.is_owner_of_truck(truck_id)
);

drop policy if exists "orders_student_insert_own" on orders;
create policy "orders_student_insert_own"
on orders
for insert
to authenticated
with check (
  customer_user_id = auth.uid()::text
);

drop policy if exists "orders_owner_update_owned_truck" on orders;
create policy "orders_owner_update_owned_truck"
on orders
for update
to authenticated
using (public.is_owner_of_truck(truck_id))
with check (public.is_owner_of_truck(truck_id));

drop policy if exists "truck_applications_owner_insert" on truck_applications;
create policy "truck_applications_owner_insert"
on truck_applications
for insert
to authenticated
with check (public.current_user_role() = 'owner');

drop policy if exists "reviews_public_read" on reviews;
create policy "reviews_public_read"
on reviews
for select
to anon, authenticated
using (true);

drop policy if exists "reviews_authenticated_insert" on reviews;
create policy "reviews_authenticated_insert"
on reviews
for insert
to authenticated
with check (true);
```

## Incremental schema updates for an existing project

Run this if your tables already exist from an earlier setup:

```sql
alter table food_trucks add column if not exists orders_paused boolean default false;
alter table food_trucks add column if not exists closed_early boolean default false;
alter table food_trucks add column if not exists active_hours text default 'Not set';
alter table food_trucks add column if not exists live_latitude double precision;
alter table food_trucks add column if not exists live_longitude double precision;
alter table menu_items add column if not exists truck_id text;
alter table orders add column if not exists customer_user_id text;

update food_trucks
set live_latitude = coalesce(live_latitude, latitude),
    live_longitude = coalesce(live_longitude, longitude);

alter table food_trucks add column if not exists closing_at timestamptz;
alter table menu_items add column if not exists tags text[] default '{}'::text[];
```

## Auth mode used

App signs in with Supabase Auth password flow:
- endpoint: `/auth/v1/token?grant_type=password`
- create users first in Supabase Auth dashboard or via signup API.
- owner/student role routing depends on `profiles`, and the app signup flow sends `role` in auth metadata for the trigger above.
- enable email confirmation in Supabase Auth settings for verification flow.

## MVP launch notes

- `orders.items` stores the full order basket as JSON so student and owner devices can reconstruct orders without relying on local-only state.
- `orders.truck_id` and `menu_items.truck_id` should be populated for every new write. `truck_name` remains only as display/legacy compatibility data.
- If you enable the RLS policies above, guest checkout will no longer be able to create real orders because `orders` inserts require an authenticated user. For a pilot, prefer real sign-in over guest ordering.

## Optional: `closing_at` and `tags`

- `food_trucks.closing_at`: ISO8601 timestamp used for “Closing soon” in the student menu header (within roughly 45 minutes of that time while the truck is still open).
- `menu_items.tags`: string array of short merchandising labels (for example `{"Best Seller"}`) shown on student menu cards.

## Repo hygiene

If `DerivedData` or other Xcode build artifacts were ever committed by mistake, remove them from git history with a tool such as [`git-filter-repo`](https://github.com/newren/git-filter-repo) and keep them ignored (this repo’s `.gitignore` already lists common paths).
