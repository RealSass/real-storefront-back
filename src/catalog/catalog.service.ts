import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

@Injectable()
export class CatalogService {
  constructor(private readonly prisma: PrismaService) {}

  // ── Admin ────────────────────────────────────────────────────────────
  async createProduct(organizationId: string, dto: CreateProductDto) {
    return this.prisma.product.create({
      data: {
        organizationId,
        name: dto.name,
        handle: dto.handle,
        description: dto.description,
        categoryId: dto.categoryId,
        status: (dto.status as any) ?? 'DRAFT',
        variants: {
          create: dto.variants.map((v) => ({
            organizationId,
            sku: v.sku,
            title: v.title,
            priceCents: v.priceCents,
            currency: v.currency ?? 'USD',
            inventory: { create: { organizationId, quantityAvailable: 0 } },
          })),
        },
      },
      include: { variants: { include: { inventory: true } } },
    });
  }

  async listProductsAdmin(organizationId: string) {
    return this.prisma.product.findMany({
      where: { organizationId },
      include: { variants: { include: { inventory: true } }, category: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updateProduct(organizationId: string, productId: string, dto: UpdateProductDto) {
    const product = await this.prisma.product.findFirst({ where: { id: productId, organizationId } });
    if (!product) throw new NotFoundException('Producto no encontrado');

    return this.prisma.product.update({
      where: { id: productId },
      data: { ...dto, status: (dto.status as any) ?? undefined },
    });
  }

  // ── Público (storefront) ─────────────────────────────────────────────
  async listProductsPublic(organizationId: string, categoryHandle?: string) {
    return this.prisma.product.findMany({
      where: {
        organizationId,
        status: 'PUBLISHED',
        ...(categoryHandle && { category: { handle: categoryHandle } }),
      },
      include: { variants: { include: { inventory: true } }, category: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getProductPublic(organizationId: string, handle: string) {
    const product = await this.prisma.product.findFirst({
      where: { organizationId, handle, status: 'PUBLISHED' },
      include: { variants: { include: { inventory: true } }, category: true },
    });
    if (!product) throw new NotFoundException('Producto no encontrado o no publicado');
    return product;
  }
}
