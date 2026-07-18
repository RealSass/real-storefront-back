// src/store/store.service.ts
//
// Resuelve el slug público de una org a su organizationId.
// Este es el único punto de entrada para el storefront multi-tenant:
// el front pasa el slug de la URL, el back devuelve id + metadatos de tienda.
//
// Invariantes de dominio:
//   - Solo orgs con enabledProducts.ecommerce === true pueden servir una tienda
//   - El slug viene de realsass-sass-back (Organization.slug), es único globalmente
//   - Esta respuesta se puede cachear en el front (staleTime: 5 min)

import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface StoreInfo {
  organizationId: string;
  slug: string;
  name: string | null;
  description: string | null;
  logoUrl: string | null;
  website: string | null;
  ecommerceEnabled: boolean;
}

@Injectable()
export class StoreService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Resuelve un slug público al contexto de tienda.
   * Lanza 404 si la org no existe o si ecommerce no está habilitado.
   *
   * Nota: La tabla Organization en ecommerce-back es una réplica ligera
   * del owner-dashboard. El upsert pasivo ocurre en cada request
   * autenticado via TenantGuard, por lo que orgs nuevas aparecen
   * aquí automáticamente tras el primer acceso desde el dashboard.
   */
  async resolveBySlug(slug: string): Promise<StoreInfo> {
    const org = await this.prisma.organization.findUnique({
      where: { slug },
    });

    if (!org) {
      throw new NotFoundException(
        `No existe una tienda con el slug "${slug}". ` +
        `Verificá que la organización esté creada y haya accedido al dashboard al menos una vez.`,
      );
    }

    // enabledProducts es JSON — { ecommerce: true, chat: false, ... }
    const enabled = (org as any).enabledProducts as Record<string, boolean> | null;
    if (!enabled?.ecommerce) {
      throw new NotFoundException(
        `La organización "${slug}" no tiene el módulo de ecommerce habilitado.`,
      );
    }

    return {
      organizationId: org.id,
      slug:           org.slug ?? slug,
      name:           org.name ?? null,
      description:    (org as any).description ?? null,
      logoUrl:        (org as any).logoUrl ?? null,
      website:        (org as any).website ?? null,
      ecommerceEnabled: true,
    };
  }
}
