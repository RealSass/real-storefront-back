import { ConflictException } from '@nestjs/common';

export class InsufficientStockError extends ConflictException {
  constructor(sku: string, requested: number, available: number) {
    super(`Stock insuficiente para SKU ${sku}: pedidos ${requested}, disponibles ${available}`);
  }
}
