/**
 * Contrato compartido con real-back (src/users/types/organization-access.types.ts)
 * y con real-config-back (src/common/types/tenant-context.ts).
 * Si cambia en real-back, debe actualizarse acá también.
 *
 * NOTA: los nombres de permisos (canViewListings, etc.) vienen de real-back
 * y hoy están pensados para el dominio de listings. Si el modelo de permisos
 * de real-back todavía no tiene granularidad por producto ("storefront"),
 * usá este mismo objeto (ya sirve para distinguir OWNER de COLLABORATOR) y
 * date por avisado: esto es candidato a ADR apenas real-back exponga
 * permissions específicos para e-commerce.
 */

export type TenantRole = 'OWNER' | 'COLLABORATOR';

export interface CollaboratorPermissions {
  canViewListings: boolean;
  canCreateListings: boolean;
  canEditListings: boolean;
  canDeleteListings: boolean;
  canViewStats: boolean;
  canManageLeads: boolean;
  canManageCollaborators: boolean;
}

export const FULL_PERMISSIONS: CollaboratorPermissions = {
  canViewListings: true,
  canCreateListings: true,
  canEditListings: true,
  canDeleteListings: true,
  canViewStats: true,
  canManageLeads: true,
  canManageCollaborators: true,
};

export interface TenantContext {
  userId: string;
  organizationId: string;
  role: TenantRole;
  permissions: CollaboratorPermissions;
  apiKeyScopes?: string[];
}
