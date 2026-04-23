-- Expose `public.orders` to Supabase Realtime (Postgres changes).
-- Safe to run once. If the table is already in the publication, you may see a notice; that's OK.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end
$$;
