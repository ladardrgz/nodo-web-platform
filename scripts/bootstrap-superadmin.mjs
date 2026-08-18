import { createClient } from "@supabase/supabase-js";

function readArgument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
const secretKey =
  process.env.SUPABASE_SECRET_KEY?.trim() ||
  process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const email = readArgument("email")?.trim().toLowerCase();

if (!email || !/^\S+@\S+\.\S+$/.test(email)) {
  throw new Error("Uso: npm run bootstrap:superadmin -- --email tu@email.com");
}

if (!url || !secretKey) {
  throw new Error(
    "Faltan NEXT_PUBLIC_SUPABASE_URL o SUPABASE_SECRET_KEY (o la clave legacy SUPABASE_SERVICE_ROLE_KEY) en .env.local.",
  );
}

const admin = createClient(url, secretKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

let user;
for (let page = 1; page <= 20 && !user; page += 1) {
  const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
  if (error) throw new Error("No se pudo consultar Supabase Auth.", { cause: error });
  user = data.users.find((candidate) => candidate.email?.toLowerCase() === email);
  if (data.users.length < 100) break;
}

if (!user) {
  throw new Error("La cuenta no existe en Supabase Auth. Registrala y confirmá su correo antes de ejecutar este comando.");
}

if (!user.email_confirmed_at) {
  throw new Error("La cuenta existe, pero el correo todavía no fue confirmado.");
}

const { data: existingProfile, error: readError } = await admin
  .from("profiles")
  .select("id,role,status,organization_id")
  .eq("id", user.id)
  .maybeSingle();

if (readError) throw new Error("No se pudo consultar el perfil de aplicación.", { cause: readError });

if (existingProfile?.role === "SUPERADMIN" && existingProfile.status === "ACTIVE" && existingProfile.organization_id === null) {
  process.stdout.write("SUPERADMIN already configured.\n");
  process.exit(0);
}

const { error: profileError } = await admin.from("profiles").upsert({
  id: user.id,
  role: "SUPERADMIN",
  status: "ACTIVE",
  organization_id: null,
});

if (profileError) throw new Error("No se pudo configurar el perfil SUPERADMIN.", { cause: profileError });

const { error: auditError } = await admin.from("audit_events").insert({
  actor_user_id: null,
  event_type: "BOOTSTRAP_SUPERADMIN",
  entity_type: "PROFILE",
  entity_id: user.id,
  metadata: { source: "trusted_local_command" },
});

if (auditError) throw new Error("El perfil fue actualizado, pero no se pudo registrar la auditoría.", { cause: auditError });

process.stdout.write("SUPERADMIN configured successfully.\n");
