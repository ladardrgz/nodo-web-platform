import type { OrganizationListItem, UserListItem } from "@/features/superadmin/types";

const workshopNames = [
  "Circuito Norte", "Punto Móvil", "Tecno Centro", "Conecta Sur", "Repara Plus", "Nodo Express",
  "Servicio Delta", "Taller Pixel", "Móvil Uno", "Diagnóstico 360", "Tecno Formosa", "Equipo Claro",
  "Solución Digital", "Repara Lab", "Conexión Técnica", "Dispositivo Sur",
];

export const developmentOrganizations: OrganizationListItem[] = workshopNames.map((name, index) => ({
  id: `development-organization-${index + 1}`,
  name,
  slug: `demo-${String(index + 1).padStart(2, "0")}`,
  status: index % 4 === 3 ? "SUSPENDED" : "ACTIVE",
  isDevelopmentMock: true,
}));

export const developmentUsers: UserListItem[] = Array.from({ length: 16 }, (_, index) => {
  const organization = developmentOrganizations[index % developmentOrganizations.length];
  const number = index + 1;
  return {
    id: `development-user-${number}`,
    firstName: index % 2 ? "Cliente" : "Propietario",
    lastName: `Demostración ${number}`,
    displayName: `${index % 2 ? "Cliente" : "Propietario"} Demostración ${number}`,
    email: `demo.usuario${number}@example.test`,
    role: index % 2 ? "CUSTOMER" : "OWNER",
    status: index % 5 === 4 ? "SUSPENDED" : index % 7 === 6 ? "DISABLED" : "ACTIVE",
    organizationId: organization.id,
    organizationName: organization.name,
    invitationPending: index % 6 === 5,
    isDevelopmentMock: true,
  };
});
