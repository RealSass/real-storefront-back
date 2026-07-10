import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { OrdersService } from './orders.service';

describe('OrdersService.checkout', () => {
  const buildDeps = (overrides: Partial<any> = {}) => {
    const prisma = {
      cart: {
        findFirst: jest.fn(),
        update: jest.fn(),
      },
      storeCustomer: { findFirst: jest.fn() },
      $transaction: jest.fn(async (fn: any) => fn(prisma)),
      order: { create: jest.fn() },
      ...overrides.prisma,
    };
    const inventoryService = { reserveWithinTransaction: jest.fn(), ...overrides.inventoryService };
    const activityService = { log: jest.fn().mockResolvedValue(undefined), ...overrides.activityService };

    return { prisma, inventoryService, activityService };
  };

  it('lanza NotFoundException si el carrito no existe', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue(null);
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-x', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(NotFoundException);
  });

  it('lanza ConflictException si el carrito ya no está ACTIVE', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({ id: 'cart-1', status: 'CONVERTED', items: [] });
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-1', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(ConflictException);
  });

  it('lanza BadRequestException si el carrito está vacío', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({ id: 'cart-1', status: 'ACTIVE', items: [] });
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-1', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(BadRequestException);
  });

  it('crea la orden y marca el carrito CONVERTED en el camino feliz', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({
      id: 'cart-1',
      status: 'ACTIVE',
      currency: 'USD',
      sessionId: 'sess-1',
      items: [
        { variantId: 'v1', quantity: 2, unitPriceCentsSnapshot: 1000, variant: { sku: 'SKU-1' } },
      ],
    });
    prisma.storeCustomer.findFirst.mockResolvedValue({ id: 'cust-1' });
    prisma.order.create.mockResolvedValue({ id: 'order-1', totalCents: 2000 });

    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    const result = await service.checkout('org-1', {
      cartId: 'cart-1',
      customerId: 'cust-1',
      shippingAddress: { line1: 'Calle 123', city: 'Catamarca', country: 'AR' } as any,
    });

    expect(inventoryService.reserveWithinTransaction).toHaveBeenCalledWith(prisma, 'v1', 'SKU-1', 2);
    expect(prisma.cart.update).toHaveBeenCalledWith({ where: { id: 'cart-1' }, data: { status: 'CONVERTED' } });
    expect(result).toEqual({ id: 'order-1', totalCents: 2000 });
  });
});
