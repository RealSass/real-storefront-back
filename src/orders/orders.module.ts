import { Module } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { OrdersController } from './orders.controller';
import { CheckoutController } from './checkout.controller';
import { InventoryModule } from '../inventory/inventory.module';
import { ActivityModule } from '../activity/activity.module';

@Module({
  imports: [InventoryModule, ActivityModule],
  controllers: [OrdersController, CheckoutController],
  providers: [OrdersService],
  exports: [OrdersService],
})
export class OrdersModule {}
