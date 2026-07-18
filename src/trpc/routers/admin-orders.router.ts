/**
 * src/trpc/routers/admin-orders.router.ts
 *
 * Vista de órdenes para el dashboard (OWNER/COLLABORATOR).
 *
 * Firmas reales:
 *   OrdersService.listOrders(organizationId)
 *   OrdersService.getOrder(organizationId, orderId)
 *
 * El checkout público (OrdersService.checkout) permanece en REST @Public()
 * para el flujo anónimo. El checkout autenticado (cliente logueado) va en
 * customer.router.ts.
 */
import { z }                     from 'zod';
import { router, adminProcedure } from '../trpc';
import type { OrdersService }    from '../../orders/orders.service';

export function createAdminOrdersRouter(ordersService: OrdersService) {
  return router({

    /**
     * adminOrders.list
     * Todas las órdenes de la org. OWNER o COLLABORATOR.
     */
    list: adminProcedure.query(async ({ ctx }) => {
      return ordersService.listOrders(ctx.organizationId);
    }),

    /**
     * adminOrders.get
     * Detalle de una orden con items, customer y statusHistory.
     */
    get: adminProcedure
      .input(z.object({ orderId: z.string().uuid() }))
      .query(async ({ ctx, input }) => {
        return ordersService.getOrder(ctx.organizationId, input.orderId);
      }),
  });
}
