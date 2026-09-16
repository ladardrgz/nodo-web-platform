# Órdenes de servicio

Flujo de ejemplo: **Asignar técnico** → componente React → Server Action → `AssignTechnicianUseCase` → `ServiceOrderRepository` → `SupabaseServiceOrderRepository` → RPC PostgreSQL → RLS, constraints y trigger.

La organización no llega desde el navegador: las RPC derivan `organization_id` de `auth.uid()` y `profiles`. `create_service_order` es idempotente por recepción y genera el número humano con un contador atómico por organización.

Los estados se leen desde `service_order_statuses`; TypeScript no conserva una segunda lista canónica de negocio. La entidad `ServiceOrder` sólo protege la invariante genérica de no transicionar desde un estado terminal.
