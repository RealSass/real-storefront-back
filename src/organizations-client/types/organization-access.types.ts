/**
 * Contrato compartido con real-back (src/users/types/organization-access.types.ts)
 * y con real-config-back. Si cambia uno, actualizar los tres.
 */
import type { TenantRole, CollaboratorPermissions } from '../../common/types/tenant-context';

export type { TenantRole, CollaboratorPermissions };

export interface OrganizationAccessResult {
  canAccess: boolean;
  userId?: string;
  organizationId?: string;
  role?: TenantRole;
  permissions?: CollaboratorPermissions;
  reason?: string;
}
