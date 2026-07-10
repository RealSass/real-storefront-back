import { Controller, Get, Param, Query } from '@nestjs/common';
import { CatalogService } from './catalog.service';
import { Public } from '../common/decorators/public.decorator';

// Público — visitantes anónimos de la tienda. Sin Firebase.
// TODO: cuando exista StorefrontSettings, validar acá que la organización
// tenga el storefront publicado antes de exponer el catálogo.
@Controller('ecommerce/public/:organizationId/products')
@Public()
export class PublicCatalogController {
  constructor(private readonly catalogService: CatalogService) {}

  @Get()
  list(@Param('organizationId') organizationId: string, @Query('category') category?: string) {
    return this.catalogService.listProductsPublic(organizationId, category);
  }

  @Get(':handle')
  get(@Param('organizationId') organizationId: string, @Param('handle') handle: string) {
    return this.catalogService.getProductPublic(organizationId, handle);
  }
}
