"use client";

import { Ban, CheckCircle2, Clock3, Search, UserRound, X } from "lucide-react";
import { useMemo, useState } from "react";

import { Pagination } from "@/components/ui/Pagination";
import { IconInput } from "@/components/ui/IconInput";
import { UserAccessForm } from "@/features/superadmin/components/UserAccessForm";
import { pageRange, paginate, SUPERADMIN_PAGE_SIZE } from "@/features/superadmin/list-utils";
import type { OrganizationOption, UserListItem } from "@/features/superadmin/types";

type UserFilter = "ALL" | "ACTIVE" | "INACTIVE" | "PENDING";

function matchesStatus(user: UserListItem, filter: UserFilter) {
  if (filter === "ALL") return true;
  if (filter === "PENDING") return user.invitationPending;
  if (filter === "ACTIVE") return !user.invitationPending && user.status === "ACTIVE";
  return !user.invitationPending && user.status !== "ACTIVE";
}

function UserStateBadge({ user }: { user: UserListItem }) {
  if (user.invitationPending) return <span className="inline-flex items-center gap-1.5 rounded-full bg-warning-soft px-2.5 py-1 text-xs font-bold text-warning ring-1 ring-inset ring-warning/25"><Clock3 className="size-3.5" />Invitación pendiente</span>;
  if (user.status === "ACTIVE") return <span className="inline-flex items-center gap-1.5 rounded-full bg-success-soft px-2.5 py-1 text-xs font-bold text-success ring-1 ring-inset ring-success/20"><CheckCircle2 className="size-3.5" />Activo</span>;
  return <span className="inline-flex items-center gap-1.5 rounded-full bg-danger-soft px-2.5 py-1 text-xs font-bold text-danger ring-1 ring-inset ring-danger/20"><Ban className="size-3.5" />{user.status === "SUSPENDED" ? "Suspendido" : "Inactivo"}</span>;
}

export function UsersList({ users, organizations, currentUserId }: { users: UserListItem[]; organizations: OrganizationOption[]; currentUserId: string }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<UserFilter>("ALL");
  const [page, setPage] = useState(1);

  const filtered = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase("es");
    return users.filter((user) => matchesStatus(user, status) && (!normalizedQuery || `${user.firstName} ${user.lastName} ${user.displayName} ${user.email} ${user.organizationName}`.toLocaleLowerCase("es").includes(normalizedQuery)));
  }, [query, status, users]);
  const visible = paginate(filtered, page);
  const range = pageRange(page, filtered.length);
  const clear = () => { setQuery(""); setStatus("ALL"); setPage(1); };

  return (
    <div>
      <div className="grid gap-3 border-b border-line p-4 sm:grid-cols-[minmax(0,1fr)_180px] sm:p-5"><label><span className="sr-only">Buscar usuarios</span><IconInput aria-label="Buscar usuarios" clearLabel="Limpiar búsqueda de usuarios" leadingIcon={<Search className="size-4" />} onChange={(event) => { setQuery(event.target.value); setPage(1); }} onClear={() => { setQuery(""); setPage(1); }} placeholder="Buscar por persona, email u organización" type="search" value={query} /></label><label><span className="sr-only">Filtrar usuarios por estado</span><select className="field-control" onChange={(event) => { setStatus(event.target.value as UserFilter); setPage(1); }} value={status}><option value="ALL">Todos</option><option value="ACTIVE">Activos</option><option value="INACTIVE">Inactivos</option><option value="PENDING">Pendientes</option></select></label></div>
      {visible.length ? <div className="divide-y divide-line">{visible.map((user) => <article className="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(220px,0.7fr)_minmax(0,1.3fr)]" key={user.id}><div><div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-full bg-accent-soft text-accent"><UserRound className="size-5" /></span><div className="min-w-0"><strong className="block text-sm text-ink">{user.displayName}</strong><span className="block truncate text-xs text-ink-muted">{user.email}</span><span className="mt-1 block text-xs text-ink-secondary">{user.organizationName || "Acceso global"}</span></div></div><div className="mt-3 flex flex-wrap gap-2"><UserStateBadge user={user} /><span className="rounded-full bg-surface-soft px-2.5 py-1 text-xs font-bold text-ink-secondary ring-1 ring-inset ring-line">{user.role === "SUPERADMIN" ? "Superadmin" : user.role === "OWNER" ? "Propietario" : user.role === "TECHNICIAN" ? "Técnico" : "Cliente"}</span>{user.isDevelopmentMock ? <span className="rounded-full bg-warning-soft px-2.5 py-1 text-xs font-bold text-warning">Dato de desarrollo</span> : null}</div></div>{user.isDevelopmentMock ? <div className="flex items-center rounded-lg border border-dashed border-line bg-surface-soft px-4 py-3 text-xs leading-5 text-ink-muted">Registro visual de desarrollo: no ejecuta acciones ni crea una identidad en Supabase Auth.</div> : <UserAccessForm currentUserId={currentUserId} organizations={organizations} user={user} />}</article>)}</div> : <div className="grid min-h-48 place-items-center px-5 py-8 text-center"><div><UserRound className="mx-auto size-8 text-ink-muted" /><p className="mt-3 font-bold text-ink">No encontramos usuarios con estos filtros.</p><button className="mt-4 inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-sm font-semibold text-accent hover:bg-accent-soft" onClick={clear} type="button"><X className="size-4" />Limpiar filtros</button></div></div>}
      {filtered.length ? <div className="space-y-3 border-t border-line px-4 py-4 sm:px-5"><p className="text-xs text-ink-muted">Mostrando {range.start}–{range.end} de {filtered.length} usuarios</p><Pagination onPageChange={setPage} page={page} pageSize={SUPERADMIN_PAGE_SIZE} totalItems={filtered.length} /></div> : null}
    </div>
  );
}
