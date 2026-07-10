import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { OrganizationsClientModule } from './organizations-client/organizations-client.module';
import { CatalogModule } from './catalog/catalog.module';
import { InventoryModule } from './inventory/inventory.module';
import { CustomersModule } from './customers/customers.module';
import { ActivityModule } from './activity/activity.module';
import { CartModule } from './cart/cart.module';
import { OrdersModule } from './orders/orders.module';
import { FirebaseAuthGuard } from './common/guards/firebase-auth.guard';

@Module({
  imports: [
    PrismaModule,
    RedisModule,
    OrganizationsClientModule,
    CatalogModule,
    InventoryModule,
    CustomersModule,
    ActivityModule,
    CartModule,
    OrdersModule,
  ],
  providers: [
    // Global — rutas con @Public() la saltan (catálogo público, cart,
    // customers/identify, activity, checkout).
    { provide: APP_GUARD, useClass: FirebaseAuthGuard },
  ],
})
export class AppModule {}
