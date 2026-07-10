import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { CatalogService } from './catalog.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { TenantGuard } from '../common/guards/tenant.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { Tenant } from '../common/decorators/tenant.decorator';
import type { TenantContext } from '../common/types/tenant-context';

// Admin — requiere Firebase + x-organization-id (FirebaseAuthGuard es global).
@Controller('ecommerce/products')
@UseGuards(TenantGuard, RolesGuard)
export class CatalogController {
  constructor(private readonly catalogService: CatalogService) {}

  @Get()
  list(@Tenant() tenant: TenantContext) {
    return this.catalogService.listProductsAdmin(tenant.organizationId);
  }

  @Post()
  @Roles('OWNER', 'COLLABORATOR')
  create(@Tenant() tenant: TenantContext, @Body() dto: CreateProductDto) {
    return this.catalogService.createProduct(tenant.organizationId, dto);
  }

  @Patch(':id')
  @Roles('OWNER', 'COLLABORATOR')
  update(@Tenant() tenant: TenantContext, @Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.catalogService.updateProduct(tenant.organizationId, id, dto);
  }
}
