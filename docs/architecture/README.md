# Arquitectura de Nodo

Nodo separa responsabilidades por módulo: `presentation → application → domain → infrastructure`.

- **Presentation** recibe eventos de React o Server Actions; no contiene SQL ni reglas críticas.
- **Application** expresa un caso de uso y coordina dependencias.
- **Domain** contiene entidades y value objects con invariantes reales.
- **Infrastructure** implementa contratos usando Supabase, RPCs y mappers.

La dirección de dependencias siempre apunta hacia el dominio. Un caso de uso conoce un contrato, nunca el SDK de Supabase.

El módulo de referencia es [`src/modules/service-orders`](../../src/modules/service-orders). La recepción es un registro físico de ingreso; la orden de servicio es el ciclo técnico/comercial posterior.
