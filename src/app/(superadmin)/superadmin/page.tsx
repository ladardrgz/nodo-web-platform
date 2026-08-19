import { Activity, Building2, CircleCheck, ShieldCheck, UserCheck, UserPlus, Users } from "lucide-react";
import type { Metadata } from "next";

import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { StatCard } from "@/components/ui/StatCard";
import { CreateOrganizationForm, InviteUserForm, ProfileAccessForm } from "@/features/superadmin/components/SuperadminForms";
import { formatDateTime } from "@/lib/format";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Superadmin" };

export default async function SuperadminPage() {
  const supabase = await createSupabaseServerClient();
  const admin = createSupabaseAdminClient();

  const [profileResult, organizationResult, activeResult, auditResult, authResult] = await Promise.all([
    supabase.from("profiles").select("id,display_name,first_name,last_name,role,status,organization_id,created_at", { count: "exact" }).order("created_at", { ascending: false }).limit(50),
    supabase.from("organizations").select("id,name,slug,status,created_at", { count: "exact" }).order("name"),
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("status", "ACTIVE"),
    supabase.from("audit_events").select("id,event_type,entity_type,created_at,actor_user_id").order("created_at", { ascending: false }).limit(8),
    admin.auth.admin.listUsers({ page: 1, perPage: 100 }),
  ]);

  const profiles = profileResult.data ?? [];
  const organizations = organizationResult.data ?? [];
  const auditEvents = auditResult.data ?? [];
  const organizationMap = new Map(organizations.map((organization) => [organization.id, organization.name]));
  const emailMap = new Map((authResult.data?.users ?? []).map((user) => [user.id, user.email]));
  const systemHealthy = !profileResult.error && !organizationResult.error && !activeResult.error && !auditResult.error && !authResult.error;

  return (
    <div className="space-y-8">
      <section className="scroll-mt-32" id="overview">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-accent">Control global de Nodo</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-primary">Resumen de plataforma</h1>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-muted">Organizaciones, identidades y actividad general. Los valores provienen directamente de Supabase; no se generan estadísticas ficticias.</p>

        <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard description="Entidades registradas en la plataforma." icon={<Building2 className="size-5" />} label="Organizaciones" value={organizationResult.count ?? 0} />
          <StatCard description="Perfiles de aplicación vinculados a Auth." icon={<Users className="size-5" />} label="Usuarios" value={profileResult.count ?? 0} />
          <StatCard description="Cuentas habilitadas actualmente." icon={<UserCheck className="size-5" />} label="Usuarios activos" tone="green" value={activeResult.count ?? 0} />
          <StatCard description="Eventos globales más recientes disponibles." icon={<Activity className="size-5" />} label="Actividad reciente" tone="violet" value={auditEvents.length} />
        </div>
      </section>

      <section className="scroll-mt-32" id="organizations">
        <div className="mb-4"><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Organizaciones</p><h2 className="mt-1 text-xl font-bold text-primary">Gestión multiempresa</h2></div>
        <div className="grid gap-5 xl:grid-cols-[minmax(320px,0.75fr)_minmax(0,1.25fr)]">
          <Card className="p-5">
            <h3 className="font-bold text-primary">Nueva organización</h3>
            <p className="mt-1 text-xs leading-5 text-muted">El slug identifica a la organización y debe ser único.</p>
            <CreateOrganizationForm />
          </Card>
          <Card className="overflow-hidden">
            <div className="border-b border-border px-5 py-4"><h3 className="font-bold text-primary">Organizaciones registradas</h3></div>
            {organizations.length ? <div className="divide-y divide-border">{organizations.map((organization) => <div className="flex items-center justify-between gap-4 px-5 py-4" key={organization.id}><div><strong className="text-sm text-primary">{organization.name}</strong><p className="mt-1 font-mono text-[11px] text-muted">{organization.slug}</p></div><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${organization.status === "ACTIVE" ? "bg-emerald-50 text-emerald-800" : "bg-amber-50 text-amber-800"}`}>{organization.status === "ACTIVE" ? "Activa" : "Suspendida"}</span></div>)}</div> : <EmptyState description="Creá la primera organización para comenzar a asignar propietarios." title="No hay organizaciones" />}
          </Card>
        </div>
      </section>

      <section className="scroll-mt-32 space-y-5" id="users">
        <div><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Usuarios</p><h2 className="mt-1 text-xl font-bold text-primary">Identidades y accesos</h2></div>
        <Card className="p-5">
          <h3 className="flex items-center gap-2 font-bold text-primary"><UserPlus className="size-5 text-accent" />Invitar usuario</h3>
          <p className="mt-1 text-xs leading-5 text-muted">La invitación envía un enlace seguro; Nodo no genera ni almacena contraseñas.</p>
          <InviteUserForm organizations={organizations} />
        </Card>

        <Card className="overflow-hidden">
          <div className="border-b border-border px-5 py-4"><h3 className="font-bold text-primary">Usuarios y permisos</h3><p className="mt-1 text-xs text-muted">Cada modificación de rol o estado queda auditada.</p></div>
          {profiles.length ? <div className="overflow-x-auto"><table className="w-full min-w-[980px] text-left"><thead><tr className="bg-surface-soft text-xs font-bold uppercase tracking-wide text-muted"><th className="px-5 py-3">Perfil</th><th className="px-5 py-3">Organización</th><th className="px-5 py-3">Acceso</th></tr></thead><tbody>{profiles.map((profile) => <tr className="border-t border-border" key={profile.id}><td className="px-5 py-4"><strong className="block text-sm text-primary">{profile.display_name || [profile.first_name, profile.last_name].filter(Boolean).join(" ") || "Sin nombre"}</strong><span className="block text-xs text-muted">{emailMap.get(profile.id) ?? "Correo no disponible"}</span><span className="font-mono text-[10px] text-slate-400">{profile.id}</span></td><td className="px-5 py-4 text-sm text-muted">{profile.organization_id ? organizationMap.get(profile.organization_id) ?? "Sin acceso" : "Global"}</td><td className="px-5 py-4"><ProfileAccessForm organizations={organizations} profile={{ id: profile.id, role: profile.role, status: profile.status, organizationId: profile.organization_id ?? "" }} /></td></tr>)}</tbody></table></div> : <EmptyState description="Los usuarios aparecerán después del primer registro o invitación." title="No hay perfiles" />}
        </Card>
      </section>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(300px,0.65fr)]">
        <section className="scroll-mt-32" id="activity">
          <Card className="h-full overflow-hidden"><div className="border-b border-border px-5 py-4"><h2 className="font-bold text-primary">Actividad reciente</h2><p className="mt-1 text-xs text-muted">Eventos sensibles registrados por la plataforma.</p></div>{auditEvents.length ? <ol className="divide-y divide-border">{auditEvents.map((event) => <li className="flex gap-3 px-5 py-4" key={event.id}><span className="mt-1.5 size-2 shrink-0 rounded-full bg-accent" /><div><strong className="text-sm text-primary">{event.event_type.replaceAll("_", " ")}</strong><p className="mt-1 text-xs text-muted">{event.entity_type} · {formatDateTime(event.created_at)}</p></div></li>)}</ol> : <EmptyState description="Los inicios de sesión y cambios administrativos aparecerán aquí." title="Sin actividad registrada" />}</Card>
        </section>
        <section className="scroll-mt-32" id="system">
          <Card className="h-full p-5"><div className="flex items-center gap-3"><span className={`grid size-10 place-items-center rounded-lg ${systemHealthy ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>{systemHealthy ? <CircleCheck className="size-5" /> : <ShieldCheck className="size-5" />}</span><div><p className="text-xs font-bold uppercase tracking-wide text-muted">Estado general</p><h2 className="mt-1 font-bold text-primary">{systemHealthy ? "Servicios conectados" : "Requiere revisión"}</h2></div></div><dl className="mt-6 space-y-4 border-t border-border pt-5 text-sm"><div className="flex justify-between gap-3"><dt className="text-muted">Autenticación</dt><dd className="font-semibold text-primary">Supabase Auth</dd></div><div className="flex justify-between gap-3"><dt className="text-muted">Acceso de datos</dt><dd className="font-semibold text-primary">RLS activo</dd></div><div className="flex justify-between gap-3"><dt className="text-muted">Rol actual</dt><dd className="font-semibold text-primary">SUPERADMIN</dd></div></dl></Card>
        </section>
      </div>
    </div>
  );
}
