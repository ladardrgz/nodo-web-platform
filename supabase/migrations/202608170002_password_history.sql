-- Password fingerprints are HMAC-SHA-256 values generated only in Nodo server actions.
create table public.password_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fingerprint text not null check (fingerprint ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now()
);
create index password_history_user_created_idx on public.password_history (user_id, created_at desc);
alter table public.password_history enable row level security;
revoke all on table public.password_history from anon, authenticated;
comment on table public.password_history is 'Fingerprints HMAC con pepper server-side; nunca contraseñas ni hashes de auth.users.';
