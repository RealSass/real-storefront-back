import { Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { InsufficientStockError } from './errors/insufficient-stock.error';

@Injectable()
export class InventoryService {
  constructor(private readonly prisma: PrismaService) {}

  async setStock(organizationId: string, variantId: string, quantityAvailable: number) {
    const inventory = await this.prisma.inventoryItem.findFirst({ where: { variantId, organizationId } });
    if (!inventory) throw new NotFoundException('Variante no encontrada para esta organización');

    return this.prisma.inventoryItem.update({ where: { variantId }, data: { quantityAvailable } });
  }

  /**
   * Reserva stock dentro de una transacción Prisma existente (tx). Se usa
   * desde el checkout — nunca se llama fuera de una transacción, para
   * evitar overselling bajo concurrencia.
   */
  async reserveWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    sku: string,
    quantity: number,
  ): Promise<void> {
    const inventory = await tx.inventoryItem.findUnique({ where: { variantId } });
    const available = (inventory?.quantityAvailable ?? 0) - (inventory?.quantityReserved ?? 0);

    if (available < quantity) {
      throw new InsufficientStockError(sku, quantity, available);
    }

    await tx.inventoryItem.update({
      where: { variantId },
      data: { quantityReserved: { increment: quantity } },
    });
  }

  async releaseWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    quantity: number,
  ): Promise<void> {
    await tx.inventoryItem.update({
      where: { variantId },
      data: { quantityReserved: { decrement: quantity } },
    });
  }
}
