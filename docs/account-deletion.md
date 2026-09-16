# Bajas con recuperación

La migración `202608270002_account_deletion_lifecycle.sql` crea un ciclo de baja reversible de 30 días para organizaciones y cuentas CUSTOMER.

## Procesamiento de vencimientos

Configurar `CRON_SECRET` exclusivamente en el servidor. `vercel.json` programa una llamada `GET` diaria a:

`/api/internal/account-deletions`

con el header:

`Authorization: Bearer <CRON_SECRET>`

Vercel adjunta automáticamente ese header al cron de producción. El endpoint usa `SUPABASE_SECRET_KEY` del servidor para finalizar solicitudes vencidas y eliminar las identidades de Supabase Auth. Es idempotente: si Auth falla, la identidad queda deshabilitada y el siguiente ciclo reintenta la limpieza.

La finalización conserva organizaciones, clientes, recepciones, fotografías y auditoría. Elimina vínculos de acceso y preferencias personales; los autores históricos pasan a `NULL` cuando se elimina una identidad de Auth.

Actualmente el único bloqueo operativo fiable es una recepción con estado `CONFIRMED`. El esquema aún no posee saldos ni órdenes de cobro; esas comprobaciones deben agregarse a las RPC cuando existan dichas fuentes de verdad.
