# Base de datos y seguridad

Las tablas de órdenes usan FK compuestas `(service_order_id, organization_id)` para evitar referencias cross-tenant, más `UNIQUE(reception_id)` y `UNIQUE(organization_id, order_number)`.

Las mutaciones importantes pasan por RPCs `SECURITY DEFINER` con `search_path` vacío y autorización interna. Las funciones trigger no son ejecutables por `anon` ni `authenticated`.

No se debe crear una migración contra una suposición local: primero se exporta e inspecciona Supabase remoto. Cuando una migración se aplica mediante `supabase db query` para evitar ejecutar una migración pendiente incompatible, se registra en el historial sólo después de una ejecución exitosa.
