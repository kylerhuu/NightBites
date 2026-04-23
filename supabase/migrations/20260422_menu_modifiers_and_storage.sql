-- Run in Supabase SQL Editor (new or recycled project).
-- 1) Persists per-item customizations the iOS app reads/writes as JSON.
-- 2) Storage bucket for menu images uploaded from the owner app.

-- ---------------------------------------------------------------------------
-- menu_items: modifier groups (matches app model: id, name, isRequired, …)
-- ---------------------------------------------------------------------------
alter table if exists public.menu_items
  add column if not exists modifier_groups jsonb not null default '[]'::jsonb;

-- ---------------------------------------------------------------------------
-- Public bucket for menu photos (iOS uploads with user JWT; everyone can read)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'menu-assets',
  'menu-assets',
  true,
  5242880, -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Allow anyone to view images (public menu browsing)
drop policy if exists "Menu assets are publicly readable" on storage.objects;
create policy "Menu assets are publicly readable"
on storage.objects
for select
to public
using (bucket_id = 'menu-assets');

-- Authenticated users can upload (owners must be signed in)
drop policy if exists "Authenticated users can upload menu assets" on storage.objects;
create policy "Authenticated users can upload menu assets"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'menu-assets');

-- Same users can update / replace their uploads
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
