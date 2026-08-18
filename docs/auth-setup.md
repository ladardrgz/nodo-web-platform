# Configuración de autenticación y seguridad

La aplicación ya contiene los flujos de Auth, pero necesita un proyecto Supabase configurado para ejecutarlos. No hay credenciales reales en el repositorio.

## 1. Variables de entorno

Copiar `.env.example` a `.env.local` y completar. En Supabase Dashboard abrir **Project Settings → API Keys** (o **Connect → App Frameworks**) para obtener:

- `NEXT_PUBLIC_SUPABASE_URL`: URL del proyecto, con formato `https://<PROJECT_REF>.supabase.co`.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: clave **Publishable**, apta para el navegador. En un proyecto con claves legacy puede usarse aquí la clave `anon`.
- `SUPABASE_SECRET_KEY`: clave **Secret**, sólo en el servidor. En un proyecto con claves legacy puede dejarse vacía y usar `SUPABASE_SERVICE_ROLE_KEY` como alternativa.
- `APP_URL`: origen canónico, sin barra final.
- `ENABLE_GOOGLE_AUTH`: mantener `false` hasta completar Google Cloud y habilitar el proveedor en Supabase.
- `AUTH_RATE_LIMIT_SECRET`: valor aleatorio de al menos 32 caracteres.
- `TRUSTED_PROXY_PROVIDER`: `none`, `vercel`, `cloudflare` o `single-proxy`. La aplicación ignora `X-Forwarded-For` cuando el proxy no está declarado.
- `ENABLE_DEMO_DATA`: mantener `false` en producción.

No anteponer `NEXT_PUBLIC_` a ninguna clave secreta ni copiar una clave Secret/service role en el navegador, en una captura o en el control de versiones.

## 2. Base de datos

En Supabase Dashboard abrir **SQL Editor → New query**, copiar el contenido completo de `supabase/migrations/202608170001_auth_foundation.sql` y pulsar **Run**. Como alternativa, un proyecto ya vinculado con Supabase CLI puede aplicar la migración mediante `supabase db push`. La migración crea:

- `organizations`, `profiles`, `customers` y `customer_user_links`;
- `audit_events` y contadores HMAC para rate limiting;
- trigger de perfil para cada alta en `auth.users`;
- funciones autorizadas para cambio obligatorio, administración y auditoría;
- RLS deny-by-default con políticas explícitas.

El registro público siempre crea un perfil `CUSTOMER`. Un rol privilegiado sólo puede asignarse mediante service role durante el bootstrap o mediante la función SQL protegida para `SUPERADMIN`.

## 3. URLs y plantillas de Auth

En Supabase Dashboard abrir **Authentication → URL Configuration**:

- **Site URL** local: `http://localhost:3000`.
- **Redirect URLs** locales: `http://localhost:3000/auth/callback`, `http://localhost:3000/auth/confirm`, `http://localhost:3000/reset-password` y `http://localhost:3000/change-password`.

Repetir esas rutas con el dominio real al desplegar.

Para el flujo SSR con token hash, configurar las plantillas de correo con enlaces equivalentes a:

- Confirmación: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email`
- Recuperación: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery`
- Invitación: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite`

Supabase debe mantener habilitada la verificación de correo. La aplicación no revela si un correo existe al solicitar recuperación o reenvío.

## 4. Google OAuth

Google es opcional y está desactivado por defecto. Con `ENABLE_GOOGLE_AUTH=false`, Nodo muestra el botón como **Próximamente** y `/auth/google` vuelve al login sin iniciar ninguna llamada OAuth. Los flujos de email y contraseña no dependen de Google.

1. Abrir [Google Cloud Console](https://console.cloud.google.com/) y seleccionar o crear un proyecto.
2. Abrir **Google Auth Platform → Branding** y completar nombre de la aplicación, correo de soporte y dominios autorizados.
3. Abrir **Audience** y definir usuarios de prueba mientras la aplicación esté en modo Testing.
4. Abrir **Data Access → Add or remove scopes**. Verificar `.../auth/userinfo.email` y `.../auth/userinfo.profile`, que Google agrega normalmente, y agregar manualmente `openid`.
5. Abrir **Clients → Create client → Web application**.
6. En **Authorized JavaScript origins** agregar `http://localhost:3000` y, posteriormente, el origen del dominio de producción.
7. En **Authorized redirect URIs** pegar exactamente el **Callback URL (for OAuth)** que muestra **Supabase Dashboard → Authentication → Sign In / Providers → Google**. Para un proyecto alojado suele ser `https://<PROJECT_REF>.supabase.co/auth/v1/callback`; no usar aquí `/auth/callback` de Nodo.
8. Crear el cliente y copiar su **Client ID** y **Client Secret**.
9. Volver a **Supabase → Authentication → Sign In / Providers → Google**, habilitar el proveedor, pegar esos dos valores y guardar.
10. El secreto de Google queda en Supabase y no debe agregarse al repositorio ni a variables `NEXT_PUBLIC_*`.
11. Sólo después de completar todos los pasos anteriores, establecer `ENABLE_GOOGLE_AUTH=true` y reiniciar Nodo.

Nodo inicia el flujo desde `/auth/google`, Supabase valida Google y vuelve a `/auth/callback`, donde el código se canjea por una sesión en cookies.

## 5. Primer SUPERADMIN

1. Aplicar primero la migración.
2. Abrir `http://localhost:3000/register`, crear la cuenta normalmente y confirmar el correo recibido.
3. Verificar que `.env.local` contiene la URL pública y `SUPABASE_SECRET_KEY` (o la clave legacy `SUPABASE_SERVICE_ROLE_KEY`) de Supabase.
4. Desde `C:\xampp\htdocs\Nodo`, ejecutar el comando real reemplazando el correo:

```powershell
npm run bootstrap:superadmin -- --email tu@email.com
```

El script sólo acepta una identidad ya existente y con correo confirmado. No recibe contraseñas, no crea identidades y no imprime secretos. El resultado correcto es:

```text
SUPERADMIN configured successfully.
```

Si ya estaba configurada, informa `SUPERADMIN already configured.`. Después hay que cerrar cualquier sesión existente e iniciar sesión nuevamente para que Nodo redirija a `/superadmin`.

## 6. Verificación manual

1. Registrar un cliente y confirmar su correo.
2. Verificar que ingrese únicamente a `/portal`.
3. Crear una organización e invitar un `OWNER` desde `/superadmin`.
4. Abrir la invitación, definir una contraseña y verificar el acceso a `/dashboard`.
5. Intentar `/superadmin` con OWNER y `/dashboard` con CUSTOMER: ambos deben responder 403.
6. Probar recuperación, logout y renovación de sesión.
7. Superar el límite de intentos y comprobar el bloqueo temporal y su recuperación.

Supabase aplica además sus límites nativos. La tabla local agrega límites persistentes por acción, identificador e IP confiable sin guardar esos valores en claro. Sus RPC sólo están concedidos a `service_role` y se invocan desde código `server-only`.
