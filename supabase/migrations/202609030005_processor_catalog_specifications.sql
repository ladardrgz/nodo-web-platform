-- Technical attributes of a processor are data, not schema migrations.  The
-- master-table action writes here after validating the CPU hierarchy.
begin;

create table if not exists public.processor_specifications (
  fk_processor_model_id uuid primary key references public.processor_models(id) on delete restrict,
  socket text,
  core_count smallint check (core_count is null or core_count > 0),
  thread_count smallint check (thread_count is null or thread_count > 0),
  base_clock_mhz integer check (base_clock_mhz is null or base_clock_mhz > 0),
  integrated_gpu text,
  desktop_supported boolean not null default true,
  notebook_supported boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (desktop_supported or notebook_supported)
);
alter table public.processor_specifications enable row level security;
create policy processor_specifications_read on public.processor_specifications for select to authenticated using (true);
revoke insert, update, delete on public.processor_specifications from anon, authenticated;

commit;
