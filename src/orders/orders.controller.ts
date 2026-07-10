import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { TenantGuard } from '../common/guards/tenant.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { Tenant } from '../common/decorators/tenant.decorator';
import type { TenantContext } from '../common/types/tenant-context';

// Admin — el dueño de la org revisa órdenes desde el dashboard.
@Controller('ecommerce/orders')
@UseGuards(TenantGuard, RolesGuard)
@Roles('OWNER', 'COLLABORATOR')
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  @Get()
  list(@Tenant() tenant: TenantContext) {
    return this.ordersService.listOrders(tenant.organizationId);
  }

  @Get(':id')
  get(@Tenant() tenant: TenantContext, @Param('id') id: string) {
    return this.ordersService.getOrder(tenant.organizationId, id);
  }
}
