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
   * Reserva stock de forma ATÓMICA dentro de una transacción Prisma existente.
   *
   * Usa $executeRaw con una condición WHERE columna-vs-columna para evitar
   * overselling bajo concurrencia. El UPDATE adquiere el row lock en Postgres
   * y evalúa la condición de stock de forma atómica — no hay ventana de
   * tiempo entre el check y el write como en el patrón read-check-update.
   *
   * Si rowsAffected === 0: la condición no se cumplió (stock insuficiente).
   * Se hace un SELECT de diagnóstico solo en el path de error para devolver
   * un mensaje informativo sin pagar ese costo en el path feliz.
   */
  async reserveWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    sku: string,
    quantity: number,
  ): Promise<void> {
    // UPDATE atómico: solo actualiza si (quantity_available - quantity_reserved) >= quantity
    const rowsAffected = await tx.$executeRaw`
      UPDATE inventory_items
      SET    quantity_reserved = quantity_reserved + ${quantity}
      WHERE  variant_id        = ${variantId}
        AND  (quantity_available - quantity_reserved) >= ${quantity}
    `;

    if (rowsAffected === 0) {
      // Path de error (frío): leer stock actual solo para el mensaje.
      const inventory = await tx.inventoryItem.findUnique({ where: { variantId } });
      const available = (inventory?.quantityAvailable ?? 0) - (inventory?.quantityReserved ?? 0);
      throw new InsufficientStockError(sku, quantity, available);
    }
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
