/**
 * src/trpc/routers/admin-inventory.router.ts
 *
 * Firma real:
 *   InventoryService.setStock(organizationId, variantId, quantityAvailable)
 *
 * NOTA: reserveWithinTransaction y releaseWithinTransaction son métodos
 * internos usados dentro de OrdersService.$transaction — no se exponen.
 */
import { z }                    from 'zod';
import { router, adminProcedure } from '../trpc';
import type { InventoryService } from '../../inventory/inventory.service';

export function createAdminInventoryRouter(inventoryService: InventoryService) {
  return router({

    /**
     * adminInventory.setStock
     * Establece el stock disponible de una variante. OWNER o COLLABORATOR.
     */
    setStock: adminProcedure
      .input(z.object({
        variantId:         z.string().uuid(),
        quantityAvailable: z.number().int().min(0),
      }))
      .mutation(async ({ ctx, input }) => {
        return inventoryService.setStock(ctx.organizationId, input.variantId, input.quantityAvailable);
      }),
  });
}
