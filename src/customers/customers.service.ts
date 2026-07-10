import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Identifica (o crea) al cliente por email, scoped a la organización, y
   * si viene cartId, adopta ese carrito anónimo al cliente recién
   * identificado — el carrito no se pierde al pasar de anónimo a conocido.
   */
  async identify(organizationId: string, email: string, displayName?: string, phone?: string, cartId?: string) {
    const customer = await this.prisma.storeCustomer.upsert({
      where: { organizationId_email: { organizationId, email } },
      update: { displayName, phone },
      create: { organizationId, email, displayName, phone, isGuest: true },
    });

    if (cartId) {
      await this.prisma.cart.updateMany({
        where: { id: cartId, organizationId, status: 'ACTIVE' },
        data: { customerId: customer.id },
      });
    }

    return customer;
  }

  async findById(organizationId: string, customerId: string) {
    return this.prisma.storeCustomer.findFirst({ where: { id: customerId, organizationId } });
  }
}
