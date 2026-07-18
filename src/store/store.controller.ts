// src/store/store.controller.ts
//
// Endpoints públicos (sin auth) para que el storefront multi-tenant
// resuelva el slug de la URL al contexto real de la organización.
//
// GET /ecommerce/public/by-slug/:slug
//   → { organizationId, slug, name, description, logoUrl, ... }
//
// El front usa este endpoint UNA VEZ al cargar /tienda/[slug]/layout.tsx
// y de ahí en adelante usa el organizationId para todos los demás fetches.

import { Controller, Get, Param } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiParam } from '@nestjs/swagger';
import { StoreService } from './store.service';
import { Public } from '../common/decorators/public.decorator';

@ApiTags('Store (public)')
@Controller('ecommerce/public')
@Public()
export class StoreController {
  constructor(private readonly storeService: StoreService) {}

  @Get('by-slug/:slug')
  @ApiOperation({
    summary: 'Resolver slug → storeInfo',
    description:
      'Endpoint público para storefront multi-tenant. ' +
      'El front llama esto al cargar la tienda para obtener el organizationId real. ' +
      'Devuelve 404 si la org no existe o si ecommerce no está habilitado.',
  })
  @ApiParam({ name: 'slug', example: 'mi-tienda' })
  resolveBySlug(@Param('slug') slug: string) {
    return this.storeService.resolveBySlug(slug);
  }
}
