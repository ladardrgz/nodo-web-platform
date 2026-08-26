const OWNER_ACTIVITY_LABELS: Record<string, string> = {
  INITIAL_SETUP_COMPLETED: "Configuración inicial completada",
  ORGANIZATION_SETUP_STEP_ONE_SAVED: "Identidad de la organización actualizada",
  ORGANIZATION_SETUP_STEP_TWO_SAVED: "Datos de contacto actualizados",
  ORGANIZATION_SETUP_STEP_THREE_SAVED: "Ubicación de la organización actualizada",
  ORGANIZATION_UPDATED: "Configuración de la organización actualizada",
  REPAIR_CREATED: "Reparación creada",
  REPAIR_READY: "Equipo listo para retirar",
  REPAIR_STATUS_CHANGED: "Estado de reparación actualizado",
  BUDGET_APPROVED: "Presupuesto aprobado",
  INVENTORY_UPDATED: "Inventario actualizado",
  USER_INVITED: "Usuario invitado",
  USER_ROLE_CHANGED: "Permisos de usuario actualizados",
  USER_STATUS_CHANGED: "Estado de usuario actualizado",
};

export function ownerActivityLabel(eventType: string): string {
  return OWNER_ACTIVITY_LABELS[eventType] ?? eventType
    .toLocaleLowerCase("es-AR")
    .replaceAll("_", " ")
    .replace(/^./u, (letter) => letter.toLocaleUpperCase("es-AR"));
}

export function ownerActivityEntityLabel(entityType: string): string {
  const labels: Record<string, string> = {
    ORGANIZATION: "Organización",
    REPAIR: "Reparación",
    USER: "Usuario",
    INVENTORY: "Inventario",
  };
  return labels[entityType] ?? "Actividad";
}
