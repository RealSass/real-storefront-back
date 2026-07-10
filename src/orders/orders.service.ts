import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { InventoryService } from '../inventory/inventory.service';
import { ActivityService } from '../activity/activity.service';
import { CheckoutDto } from './dto/checkout.dto';

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly inventoryService: InventoryService,
    private readonly activityService: ActivityService,
  ) {}

  /**
   * Convierte un carrito ACTIVE en una orden PENDING_PAYMENT. Reserva de
   * stock y creación de orden van en UNA transacción — evita overselling
   * bajo concurrencia. El cobro real (pasarela-pagos) se conecta después:
   * paymentIntentId queda null hasta ese momento.
   */
  async checkout(organizationId: string, dto: CheckoutDto) {
    const cart = await this.prisma.cart.findFirst({
      where: { id: dto.cartId, organizationId },
      include: { items: { include: { variant: true } } },
    });
    if (!cart) throw new NotFoundException('Carrito no encontrado');
    if (cart.status !== 'ACTIVE') throw new ConflictException(`El carrito ${cart.id} ya no está activo`);
    if (cart.items.length === 0) throw new BadRequestException('El carrito está vacío');

    const customer = await this.prisma.storeCustomer.findFirst({
      where: { id: dto.customerId, organizationId },
    });
    if (!customer) throw new NotFoundException('Cliente no encontrado');

    const shippingCents = dto.shippingCents ?? 0;
    const subtotalCents = cart.items.reduce((sum, item) => sum + item.unitPriceCentsSnapshot * item.quantity, 0);
    const totalCents = subtotalCents + shippingCents;

    const order = await this.prisma.$transaction(async (tx) => {
      for (const item of cart.items) {
        await this.inventoryService.reserveWithinTransaction(tx, item.variantId, item.variant.sku, item.quantity);
      }

      const created = await tx.order.create({
        data: {
          organizationId,
          customerId: customer.id,
          cartId: cart.id,
          currency: cart.currency,
          subtotalCents,
          shippingCents,
          totalCents,
          shippingAddress: dto.shippingAddress as any,
          items: {
            create: cart.items.map((item) => ({
              variantId: item.variantId,
              quantity: item.quantity,
              unitPriceCentsSnapshot: item.unitPriceCentsSnapshot,
            })),
          },
          statusHistory: { create: { toStatus: 'PENDING_PAYMENT', reason: 'Orden creada desde carrito' } },
        },
      });

      await tx.cart.update({ where: { id: cart.id }, data: { status: 'CONVERTED' } });

      return created;
    });

    await this.activityService
      .log(organizationId, cart.sessionId, 'ORDER_COMPLETED', customer.id, { orderId: order.id })
      .catch(() => undefined);

    // TODO: cuando se conecte pasarela-pagos, acá se crea el PaymentIntent
    // y se guarda paymentIntentId. Hoy la orden queda en PENDING_PAYMENT.
    return order;
  }

  async listOrders(organizationId: string) {
    return this.prisma.order.findMany({
      where: { organizationId },
      include: { items: true, customer: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getOrder(organizationId: string, orderId: string) {
    const order = await this.prisma.order.findFirst({
      where: { id: orderId, organizationId },
      include: { items: { include: { variant: true } }, customer: true, statusHistory: true },
    });
    if (!order) throw new NotFoundException('Orden no encontrada');
    return order;
  }
}
