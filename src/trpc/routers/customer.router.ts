/**
 * src/trpc/routers/customer.router.ts
 *
 * Procedures para clientes del storefront autenticados.
 * El cliente se identifica con x-customer-id (obtenido tras identify()).
 *
 * Firmas reales:
 *   CustomersService.findById(organizationId, customerId)
 *   OrdersService.listOrders(organizationId)   ← filtramos por customerId abajo
 *   OrdersService.getOrder(organizationId, orderId)
 *   OrdersService.checkout(organizationId, dto)
 *     dto: { cartId, customerId, shippingAddress, shippingCents? }
 *   CartService.addItem(orgId, sessionId, variantId, quantity, cartId?)
 *   CartService.removeItem(orgId, cartId, variantId)
 *   CartService.getCart(orgId, cartId)
 *
 * IMPORTANTE: checkout() llama internamente a inventoryService.reserveWithinTransaction
 * dentro de una $transaction. No tocar esa lógica — es el fix del race condition de stock.
 */
import { z }                   from 'zod';
import { TRPCError }           from '@trpc/server';
import { router, customerProcedure } from '../trpc';
import type { CustomersService } from '../../customers/customers.service';
import type { OrdersService }    from '../../orders/orders.service';
import type { CartService }      from '../../cart/cart.service';

const ShippingAddressInput = z.object({
  line1:      z.string().min(1),
  line2:      z.string().optional(),
  city:       z.string().min(1),
  province:   z.string().optional(),
  postalCode: z.string().optional(),
  country:    z.string().min(1),
});

export function createCustomerRouter(
  customersService: CustomersService,
  ordersService:    OrdersService,
  cartService:      CartService,
) {
  return router({

    /**
     * customer.me
     * Perfil del cliente autenticado.
     */
    me: customerProcedure.query(async ({ ctx }) => {
      const customer = await customersService.findById(ctx.organizationId, ctx.customerId);
      if (!customer) {
        throw new TRPCError({ code: 'NOT_FOUND', message: 'Cliente no encontrado' });
      }
      return customer;
    }),

    /**
     * customer.orders
     * Órdenes del cliente autenticado.
     * listOrders devuelve todas las de la org — filtramos por customerId.
     */
    orders: customerProcedure.query(async ({ ctx }) => {
      const all = await ordersService.listOrders(ctx.organizationId) as any[];
      return all.filter((o: any) => o.customerId === ctx.customerId);
    }),

    /**
     * customer.orderDetail
     * Detalle de una orden. Verifica que pertenezca al cliente.
     */
    orderDetail: customerProcedure
      .input(z.object({ orderId: z.string().uuid() }))
      .query(async ({ ctx, input }) => {
        const order = await ordersService.getOrder(ctx.organizationId, input.orderId) as any;
        if (order.customerId !== ctx.customerId) {
          throw new TRPCError({ code: 'FORBIDDEN', message: 'Esta orden no te pertenece' });
        }
        return order;
      }),

    // ─── Carrito ─────────────────────────────────────────────────────────────

    /**
     * customer.cart.get
     * Obtiene el carrito por ID.
     */
    cartGet: customerProcedure
      .input(z.object({ cartId: z.string().uuid() }))
      .query(async ({ ctx, input }) => {
        return cartService.getCart(ctx.organizationId, input.cartId);
      }),

    /**
     * customer.cart.addItem
     * Agrega un ítem al carrito.
     * sessionId: identificador de sesión del browser (uuid generado en el front).
     */
    cartAddItem: customerProcedure
      .input(z.object({
        sessionId: z.string(),
        variantId: z.string().uuid(),
        quantity:  z.number().int().min(1),
        cartId:    z.string().uuid().optional(),
      }))
      .mutation(async ({ ctx, input }) => {
        return cartService.addItem(
          ctx.organizationId,
          input.sessionId,
          input.variantId,
          input.quantity,
          input.cartId,
        );
      }),

    /**
     * customer.cart.removeItem
     * Elimina una variante del carrito.
     */
    cartRemoveItem: customerProcedure
      .input(z.object({
        cartId:    z.string().uuid(),
        variantId: z.string().uuid(),
      }))
      .mutation(async ({ ctx, input }) => {
        return cartService.removeItem(ctx.organizationId, input.cartId, input.variantId);
      }),

    /**
     * customer.checkout
     * Convierte el carrito en orden.
     * Llama a OrdersService.checkout() que ejecuta reserveWithinTransaction
     * atómicamente — no tocar la lógica interna.
     */
    checkout: customerProcedure
      .input(z.object({
        cartId:          z.string().uuid(),
        shippingAddress: ShippingAddressInput,
        shippingCents:   z.number().int().min(0).optional(),
      }))
      .mutation(async ({ ctx, input }) => {
        return ordersService.checkout(ctx.organizationId, {
          cartId:          input.cartId,
          customerId:      ctx.customerId,   // viene del header verificado
          shippingAddress: input.shippingAddress as any,
          shippingCents:   input.shippingCents,
        } as any);
      }),
  });
}
