import { Module } from '@nestjs/common';
import { StoreModule } from './store/store.module';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
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
import { TrpcModule }        from './trpc/trpc.module';

@Module({
  imports: [
    StoreModule,
    // 30 requests por minuto por IP — aplica a todas las rutas incluyendo @Public().
    // Las rutas de escritura públicas (activity, cart, checkout) son el vector
    // de abuso más evidente: este throttler es la primera línea de defensa.
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60_000, // 1 minuto en ms
        limit: 30,
      },
    ]),
    PrismaModule,
    RedisModule,
    OrganizationsClientModule,
    CatalogModule,
    InventoryModule,
    CustomersModule,
    ActivityModule,
    CartModule,
    OrdersModule,
    TrpcModule,
  ],
  providers: [
    // FirebaseAuthGuard primero — si la ruta es @Public() pasa directo.
    // ThrottlerGuard segundo — limita por IP independientemente de auth.
    { provide: APP_GUARD, useClass: FirebaseAuthGuard },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
