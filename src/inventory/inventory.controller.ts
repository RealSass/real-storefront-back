import { Body, Controller, Param, Patch, UseGuards } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { UpdateStockDto } from './dto/update-stock.dto';
import { TenantGuard } from '../common/guards/tenant.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { Tenant } from '../common/decorators/tenant.decorator';
import type { TenantContext } from '../common/types/tenant-context';

@Controller('ecommerce/inventory')
@UseGuards(TenantGuard, RolesGuard)
export class InventoryController {
  constructor(private readonly inventoryService: InventoryService) {}

  @Patch(':variantId')
  @Roles('OWNER', 'COLLABORATOR')
  setStock(@Tenant() tenant: TenantContext, @Param('variantId') variantId: string, @Body() dto: UpdateStockDto) {
    return this.inventoryService.setStock(tenant.organizationId, variantId, dto.quantityAvailable);
  }
}
