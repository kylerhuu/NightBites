# New / empty Supabase project (NightBites)

Use this when you created a **new** Supabase project and there is no data or schema yet.

## 1. iOS app keys

In Xcode target **Info** (or `Info.plist`):

- `SUPABASE_URL` = `https://<project-ref>.supabase.co`
- `SUPABASE_ANON_KEY` = your project **anon** public key (Settings → API)

## 2. Create tables

Open **Supabase → SQL** and run the full block from the main [SUPABASE_SETUP.md](/SUPABASE_SETUP.md) (campuses, food_trucks, menu_items, orders, reviews, profiles, and optional policies you need).

Ensure `menu_items` includes the `modifier_groups` column (it is in that doc’s `create table` snippet).

## 3. Migrations

Run, in order:

1. [20260224_add_order_payment_columns.sql](/supabase/migrations/20260224_add_order_payment_columns.sql) — only if you created `orders` before those columns existed.
2. [20260422_menu_modifiers_and_storage.sql](/supabase/migrations/20260422_menu_modifiers_and_storage.sql) — adds `modifier_groups` if missing, creates **menu-assets** storage and policies for photo uploads.

## 4. Seed a campus (required for the app to show a campus list)

```sql
insert into public.campuses (name, latitude, longitude)
values ('UCLA', 34.0689, -118.4452)
on conflict (name) do nothing;
```

Add more rows for each campus you want in the app.

## 5. Auth

Enable **Email** (and any other providers) under Authentication → Providers. Users must sign in when using Supabase mode (the app does not use guest access with a real backend).

## 6. Storage

After step 3, the **menu-assets** bucket should exist. If the migration failed on policies (e.g. policy names already used), check **Storage** in the dashboard and create the bucket manually as **public**, then re-run the policy part of the migration or adjust policy names to be unique.

## 7. Test flow

1. Create an **owner** account, sign in, create a truck, add a menu item with a **photo** from the library.
2. Sign in as a **student**, find the truck, and confirm the menu image and any **customizations** you defined on the item.

If menu photos fail to upload, confirm you are **authenticated**, the bucket **menu-assets** exists, and the storage policies above are active.
