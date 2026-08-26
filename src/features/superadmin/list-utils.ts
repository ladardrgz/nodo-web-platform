export const SUPERADMIN_PAGE_SIZE = 5;

export function paginate<T>(items: T[], page: number, pageSize = SUPERADMIN_PAGE_SIZE): T[] {
  const safePage = Math.max(1, page);
  return items.slice((safePage - 1) * pageSize, safePage * pageSize);
}

export function pageRange(page: number, totalItems: number, pageSize = SUPERADMIN_PAGE_SIZE) {
  if (!totalItems) return { start: 0, end: 0 };
  return {
    start: (page - 1) * pageSize + 1,
    end: Math.min(page * pageSize, totalItems),
  };
}
