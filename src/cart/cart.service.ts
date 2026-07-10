import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ActivityService } from '../activity/activity.service';

@Injectable()
export class CartService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityService: ActivityService,
  ) {}

  private async getOrCreateActiveCart(organizationId: string, sessionId: string, cartId?: string) {
    if (cartId) {
      const existing = await this.prisma.cart.findFirst({ where: { id: cartId, organizationId, status: 'ACTIVE' } });
      if (existing) return existing;
    }

    return this.prisma.cart.create({
      data: { organizationId, sessionId, status: 'ACTIVE', currency: 'USD' },
    });
  }

  async addItem(organizationId: string, sessionId: string, variantId: string, quantity: number, cartId?: string) {
    const variant = await this.prisma.productVariant.findFirst({ where: { id: variantId, organizationId } });
    if (!variant) throw new NotFoundException('Variante no encontrada');

    const cart = await this.getOrCreateActiveCart(organizationId, sessionId, cartId);

    const item = await this.prisma.cartItem.upsert({
      where: { cartId_variantId: { cartId: cart.id, variantId } },
      update: { quantity: { increment: quantity } },
      create: {
        cartId: cart.id,
        variantId,
        quantity,
        unitPriceCentsSnapshot: variant.priceCents,
      },
    });

    await this.activityService
      .log(organizationId, sessionId, 'CART_ADD', cart.customerId ?? undefined, { variantId, quantity })
      .catch(() => undefined);

    return this.getCart(organizationId, cart.id);
  }

  async removeItem(organizationId: string, cartId: string, variantId: string) {
    const cart = await this.prisma.cart.findFirst({ where: { id: cartId, organizationId } });
    if (!cart) throw new NotFoundException('Carrito no encontrado');

    await this.prisma.cartItem.deleteMany({ where: { cartId, variantId } });
    return this.getCart(organizationId, cartId);
  }

  async getCart(organizationId: string, cartId: string) {
    const cart = await this.prisma.cart.findFirst({
      where: { id: cartId, organizationId },
      include: { items: { include: { variant: true } } },
    });
    if (!cart) throw new NotFoundException('Carrito no encontrado');
    return cart;
  }
}
