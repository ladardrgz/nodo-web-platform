-- Las escrituras del domicilio pasan exclusivamente por la RPC validada y auditada.
revoke insert, update, delete on table public.organization_addresses from anon, authenticated;

comment on table public.organization_addresses is
  'Domicilio principal estructurado. Lectura protegida por RLS; escritura exclusivamente mediante RPC autorizada y auditada.';
