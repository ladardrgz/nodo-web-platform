import { UserPlus } from "lucide-react";
import type { Metadata } from "next";

import { Card } from "@/components/ui/Card";
import { ActivityList } from "@/features/superadmin/components/ActivityList";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { OrganizationsList } from "@/features/superadmin/components/OrganizationsList";
import { CreateOrganizationForm, InviteUserForm } from "@/features/superadmin/components/SuperadminForms";
import { OrganizationHelp } from "@/features/superadmin/components/OrganizationHelp";
import { SuperadminOverview } from "@/features/superadmin/components/SuperadminOverview";
import { SystemStatus } from "@/features/superadmin/components/SystemStatus";
import { UsersList } from "@/features/superadmin/components/UsersList";
import { developmentOrganizations, developmentUsers } from "@/features/superadmin/development-data";
import type { OrganizationListItem, UserListItem } from "@/features/superadmin/types";
import { requireRole } from "@/lib/auth/session";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Superadmin" };

export default async function SuperadminPage() {
  const context = await requireRole(["SUPERADMIN"]);
  const supabase = await createSupabaseServerClient();
  const admin = createSupabaseAdminClient();

  const [profileResult, organizationResult, activeResult, auditResult, authResult, storageResult] = await Promise.all([
    supabase.from("profiles").select("id,display_name,first_name,last_name,role,status,organization_id,created_at", { count: "exact" }).order("created_at", { ascending: false }).limit(1000),
    supabase.from("organizations").select("id,name,slug,status,created_at", { count: "exact" }).order("name"),
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("status", "ACTIVE"),
    supabase.from("audit_events").select("id,event_type,entity_type,created_at,actor_user_id", { count: "exact" }).order("created_at", { ascending: false }).limit(5),
    admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    admin.storage.listBuckets(),
  ]);

  const profiles = profileResult.data ?? [];
  const organizations = organizationResult.data ?? [];
  const auditEvents = auditResult.data ?? [];
  const authUsers = authResult.data?.users ?? [];
  const authUserMap = new Map(authUsers.map((user) => [user.id, user]));
  const organizationMap = new Map(organizations.map((organization) => [organization.id, organization.name]));
  const organizationOptions = organizations.map(({ id, name, slug }) => ({ id, name, slug }));
  const organizationRows: OrganizationListItem[] = organizations.map(({ id, name, slug, status }) => ({ id, name, slug, status }));
  const userRows: UserListItem[] = profiles.map((profile) => {
    const authUser = authUserMap.get(profile.id);
    return {
      id: profile.id,
      firstName: profile.first_name ?? "",
      lastName: profile.last_name ?? "",
      displayName: profile.display_name || [profile.first_name, profile.last_name].filter(Boolean).join(" ") || "Sin nombre",
      email: authUser?.email ?? "Correo no disponible",
      role: profile.role,
      status: profile.status,
      organizationId: profile.organization_id ?? "",
      organizationName: profile.organization_id ? organizationMap.get(profile.organization_id) ?? "Organización no disponible" : "Acceso global",
      invitationPending: Boolean(authUser?.invited_at && !authUser.email_confirmed_at),
    };
  });
  const displayedOrganizations = process.env.NODE_ENV === "development" ? [...organizationRows, ...developmentOrganizations] : organizationRows;
  const displayedUsers = process.env.NODE_ENV === "development" ? [...userRows, ...developmentUsers] : userRows;
  const existingEmails = authUsers.flatMap((user) => user.email ? [user.email] : []);
  const activityRows = auditEvents.map((event) => ({ id: event.id, eventType: event.event_type, entityType: event.entity_type, createdAt: event.created_at }));
  const systemHealthy = !profileResult.error && !organizationResult.error && !activeResult.error && !auditResult.error && !authResult.error;
  const firstName = context.profile.first_name || context.profile.display_name?.split(" ")[0] || "Superadmin";

  return (
    <div className="space-y-8">
      <SuperadminOverview activeUsers={activeResult.count ?? 0} firstName={firstName} organizations={organizationResult.count ?? 0} recentActivity={auditResult.count ?? auditEvents.length} systemHealthy={systemHealthy} users={profileResult.count ?? 0} />

      <section className="scroll-mt-32" id="organizations">
        <div className="mb-4 flex items-start justify-between gap-4"><div><div className="flex items-center gap-2"><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Organizaciones</p><OrganizationHelp /></div><h2 className="mt-1 text-xl font-bold text-primary">Gestión multiempresa</h2><p className="mt-2 max-w-2xl text-sm leading-6 text-muted">Cada organización representa un taller o espacio de trabajo independiente creado para uno de tus clientes administradores.</p></div></div>
        <div className="grid gap-5 xl:grid-cols-[minmax(320px,0.75fr)_minmax(0,1.25fr)]">
          <Card className="p-5 sm:p-6">
            <h3 className="font-bold text-primary">Nueva organización</h3>
            <p className="mt-1 text-xs leading-5 text-muted">Creá un espacio de trabajo separado para un cliente administrador.</p>
            <CreateOrganizationForm organizations={organizationOptions} />
          </Card>
          <Card className="overflow-hidden">
            <div className="border-b border-border px-5 py-4"><h3 className="font-bold text-primary">Organizaciones registradas</h3></div>
            <OrganizationsList organizations={displayedOrganizations} />
          </Card>
        </div>
      </section>

      <section className="scroll-mt-32 space-y-5" id="users">
        <div><div className="flex items-center gap-2"><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Usuarios</p><ContextHelp label="Explicar qué significa invitar un usuario" title="¿Qué significa invitar un usuario?">Invitar un usuario permite crear acceso a Nodo mediante un enlace seguro. El usuario deberá activar su cuenta antes de ingresar. Nodo no debe generar ni almacenar contraseñas permanentes manualmente.</ContextHelp></div><h2 className="mt-1 text-xl font-bold text-primary">Identidades y accesos</h2></div>
        <Card className="p-5">
          <h3 className="flex items-center gap-2 font-bold text-primary"><UserPlus className="size-5 text-accent" />Invitar usuario</h3>
          <p className="mt-1 text-xs leading-5 text-muted">La invitación envía un enlace seguro; Nodo no genera ni almacena contraseñas.</p>
          <InviteUserForm existingEmails={existingEmails} organizations={organizationOptions} />
        </Card>

        <Card className="overflow-hidden">
          <div className="border-b border-border px-5 py-4"><h3 className="font-bold text-primary">Usuarios y permisos</h3><p className="mt-1 text-xs text-muted">Cada modificación de rol o estado queda auditada.</p></div>
          <UsersList currentUserId={context.userId} organizations={organizationOptions} users={displayedUsers} />
        </Card>
      </section>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(300px,0.65fr)]">
        <section className="scroll-mt-32" id="activity">
          <Card className="h-full overflow-hidden"><ActivityList events={activityRows} totalItems={auditResult.count ?? activityRows.length} /></Card>
        </section>
        <section className="scroll-mt-32" id="system">
          <SystemStatus services={[
            { name: "Base de datos", status: profileResult.error || organizationResult.error || auditResult.error ? "ERROR" : "VERIFIED", detail: profileResult.error || organizationResult.error || auditResult.error ? "La comprobación de lectura falló." : "Consultas protegidas respondieron correctamente." },
            { name: "Autenticación", status: authResult.error ? "ERROR" : "VERIFIED", detail: authResult.error ? "Supabase Auth no respondió correctamente." : "La API administrativa respondió correctamente." },
            { name: "Storage", status: storageResult.error ? "ERROR" : "VERIFIED", detail: storageResult.error ? "No se pudo verificar Supabase Storage." : "La API de buckets respondió correctamente." },
            { name: "Correo", status: "NOT_CONFIGURED", detail: "SMTP/PHPMailer propio no está configurado en Nodo." },
          ]} />
        </section>
      </div>
    </div>
  );
}
