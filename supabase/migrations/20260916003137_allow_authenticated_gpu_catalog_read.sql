-- GPU catalog is global and read-only from the client.  RLS was enabled but
-- had no SELECT policy, leaving the Notebook selectors empty for authenticated users.
begin;

create policy gpu_brands_read
on public.gpu_brands
for select to authenticated
using (is_active);

create policy gpu_families_read
on public.gpu_families
for select to authenticated
using (is_active);

create policy gpu_models_read
on public.gpu_models
for select to authenticated
using (is_active);

revoke insert, update, delete on public.gpu_brands, public.gpu_families, public.gpu_models from anon, authenticated;

commit;
