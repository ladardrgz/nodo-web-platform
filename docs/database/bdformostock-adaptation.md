# Adaptación de `bdformostock_schema.sql`

El archivo legado se usó únicamente como fuente de referencia y dataset. No se ejecuta, no se copia al repositorio y no reemplaza el esquema de Nodo.

## Estado previo comprobado

Las migraciones existentes y el proyecto Supabase enlazado ya contenían:

- `countries`: 1 fila (`AR`, Argentina).
- `provinces`: 24 jurisdicciones argentinas, incluida `34`, Formosa.
- `localities`: 1 fila (`34014020`, Formosa).
- `neighborhoods`: 0 filas.
- `organization_addresses`: la estructura solicitada de domicilio, sin necesidad de reemplazo.
- `organizations`, `profiles`, `customers`, roles, Supabase Auth, auditoría y RLS multiempresa.

## Mapa de las 41 tablas legadas

| Tabla legado | ¿Se usa? | Destino Nodo | Acción |
| --- | --- | --- | --- |
| `tb_paises` | Sí, datos | `countries` | Reutilizar Argentina ya existente; no duplicar. |
| `tb_provincias` | Sí, comparación | `provinces` | Conservar las 24 jurisdicciones oficiales ya existentes; no acortar el nombre oficial de Tierra del Fuego. |
| `tb_localidades` | Sí, datos | `localities` | Reutilizar Formosa y cargar los otros 15 nombres del dataset con IDs estables de Nodo. |
| `tb_barrios` | Sí, datos | `neighborhoods` | Cargar los 118 barrios, todos relacionados con Formosa capital como indica el SQL fuente. |
| `tb_domicilios` | Solo comparación | `organization_addresses` | No migrar datos ficticios; la estructura actual ya es más completa. |
| `tb_estados_logicos` | No | — | Descartar el catálogo sobrecargado que mezcla estados de dominios incompatibles. |
| `tb_tipo_documentos` | No en este incremento | — | Fuera del alcance de geografía/inventario. |
| `tb_detalle_documento` | No | — | Contiene documentos personales de demo. |
| `tb_tipo_contacto` | No | `customers`/`suppliers` | Nodo usa campos de contacto explícitos. |
| `tb_detalle_contacto` | No | `customers`/`suppliers` | No migrar contactos ficticios. |
| `tb_personas_fisicas` | No | `profiles`/`customers` | No importar personas; los modelos actuales son la fuente de verdad. |
| `tb_domicilios_personas` | No | — | Relaciones y domicilios ficticios. |
| `tb_permisos` | No | RLS actual | No reemplazar autorización de Nodo. |
| `tb_roles` | No | `app_role`/`profiles` | No reemplazar roles actuales. |
| `tb_rolespermisos` | No | RLS actual | No migrar la matriz antigua. |
| `tb_usuarios` | No | Supabase Auth/`profiles` | Descartar usuarios, correos y hashes MD5. |
| `tb_sesiones` | No | Supabase Auth | No migrar sesiones antiguas. |
| `tb_clientes` | Solo estructura comparada | `customers` | No insertar clientes legados. |
| `tb_personas_juridicas` | Sí, concepto | `suppliers.legal_name` | Reutilizar la idea de razón social, sin datos. |
| `tb_categorias_productos` | Sí, concepto | `inventory_categories` | Crear un catálogo global reducido a ocho categorías útiles para servicio técnico. |
| `tb_marcas_productos` | Sí, concepto | `inventory_brands` | Crear catálogo privado por organización, sin importar marcas legadas ni mezclarlo con `device_brands`. |
| `tb_tipo_impuestos` | No | — | Facturación fuera del alcance. |
| `tb_detalle_impuestos` | No | — | Facturación fuera del alcance. |
| `tb_proveedores` | Sí, estructura | `suppliers` | Crear proveedor multiempresa; no cargar empresas ficticias. |
| `tb_productos` | Sí, estructura | `inventory_items` | Adaptar nombre, descripción, costo, precio, stock mínimo, SKU, categoría, marca y proveedor. No importar sus 60 productos. |
| `tb_ordenes_compra` | No todavía | — | Compras fuera del alcance del incremento. |
| `tb_detalle_orden_compra` | No todavía | — | Compras fuera del alcance del incremento. |
| `tb_sucursal` | No | `organizations` | No duplicar la separación organizacional existente. |
| `tb_inventario_sucursal` | Sí, concepto | `inventory_items` + `inventory_movements` | Reemplazar stock por sucursal con saldo por organización e historial trazable. No cargar stock aleatorio. |
| `tb_caja` | No | — | Caja fuera del alcance. |
| `tb_formas_pago` | No | — | Cobros fuera del alcance. |
| `tb_transacciones_pago_caja` | No | — | Cobros fuera del alcance. |
| `tb_periodos` | No | — | Reportes/ventas fuera del alcance. |
| `tb_factura_cabecera` | No | — | Facturación fuera del alcance. |
| `tb_factura_detalle` | No | — | Facturación y datos de demo fuera del alcance. |
| `tb_periodo_productos` | No | — | Agregado de ventas derivable; fuera del alcance. |
| `tb_historial_ventas_clientes` | No | — | Historial de ventas ficticio. |
| `tb_tipos_notas` | No | — | Notas y devoluciones fuera del alcance. |
| `tb_devoluciones` | No | — | Devoluciones fuera del alcance. |
| `tb_notas_personas` | No | — | Facturación fuera del alcance. |
| `tb_auditoria_tablas` | No | `audit_events` | No migrar auditoría antigua; Nodo ya posee auditoría compatible con Auth y organizaciones. |

## Procedimientos y triggers legados

- `sp_incrementar_stock_sucursal` y los triggers que actualizan stock se reemplazan conceptualmente por `record_inventory_movement`, que bloquea el artículo, valida el saldo, actualiza `current_stock` y registra el movimiento en una única transacción.
- Los triggers de facturas, ventas, caja y estados de producto se descartan porque sus dominios no se implementan en este incremento y dependen de IDs mágicos.
- Los movimientos de inventario son inmutables; una corrección se registra como otro movimiento `ADJUSTMENT`.

## Clasificación de datos

### A. Importar a producción

- Argentina y las 24 jurisdicciones ya existentes en Nodo: se conservan y validan.
- Los 16 nombres de `tb_localidades` para Formosa: Formosa ya existía y se agregan 15.
- Los 118 barrios de `tb_barrios`, relacionados con Formosa capital.
- Ocho categorías globales adaptadas al dominio del servicio técnico.

### B. Reutilizar solo estructura

- Categorías, marcas, proveedores, productos, saldo de inventario y trazabilidad de movimientos.
- Razón social y medios de contacto básicos de proveedores.
- Separación de costo y precio de venta.

### C. Solo demo/desarrollo

- Los 60 productos, sus precios, órdenes de compra, facturas, cajas, clientes, proveedores y sucursales concretos.
- El stock generado con `RAND()`.

No se cargan en ningún ambiente mediante estas migraciones.

### D. Descartar

- Usuarios, contraseñas MD5, sesiones, roles, permisos y documentos personales.
- Auditoría, estados lógicos globales, impuestos, facturación, ventas, caja, devoluciones y triggers asociados.

## Decisiones de integridad

- Geografía conserva las PK de texto existentes (`AR`, códigos GeoRef) y usa IDs `fs-*` solamente para filas sin código oficial en el dataset recibido.
- Los nombres visibles no se transforman. `normalized_name` elimina diferencias de mayúsculas, espacios y diacríticos para evitar duplicados bajo el mismo padre.
- `inventory_items.current_stock` es un saldo materializado, pero no puede modificarse directamente: solo `record_inventory_movement` lo cambia junto con el historial.
- Un `OUT` nunca puede dejar stock negativo. `ADJUSTMENT` admite una diferencia positiva o negativa, pero conserva la misma regla de saldo final.
- Las FKs compuestas impiden enlazar un artículo con una marca, proveedor o movimiento de otra organización.
- Las marcas de inventario permanecen separadas de `device_brands` para evitar ambigüedad entre la marca del dispositivo y la del repuesto.
