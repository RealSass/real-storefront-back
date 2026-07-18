/**
 * src/trpc/trpc.module.ts — realsass-ecommerce-back
 *
 * Monta el adapter tRPC en /api/v1/trpc.
 *
 * Auth flow para admins (OWNER/COLLABORATOR):
 *   1. applyFirebaseAuth → verifica token Firebase → inyecta req.user
 *   2. applyTenantContext → llama a OrganizationsClientService.getAccess()
 *                           (mismo que TenantGuard, con cache Redis)
 *                           → inyecta req.tenant
 *   3. Adapter tRPC → crea context con uid + organizationId + role
 *
 * Auth flow para clientes del storefront:
 *   1. applyFirebaseAuth → NO es obligatorio (clientes no usan Firebase)
 *   2. El x-customer-id header viene directo en el request
 *   3. customerProcedure lo valida en el middleware enforceCustomer
 *
 * IMPORTANTE: OrganizationsClientService ya existe en este back y tiene
 * cache Redis de 30s. No duplicamos la lógica — la reutilizamos.
 */
import {
  Module,
  Injectable,
  type NestModule,
  type MiddlewareConsumer,
} from '@nestjs/common';
import { createExpressMiddleware }          from '@trpc/server/adapters/express';
import type { Request, Response, NextFunction } from 'express';
import * as admin                           from 'firebase-admin';

import { createEcommerceAppRouter }         from './app-router';
import { createTrpcContext }                from './trpc';

import { CatalogService }                   from '../catalog/catalog.service';
import { InventoryService }                 from '../inventory/inventory.service';
import { OrdersService }                    from '../orders/orders.service';
import { CustomersService }                 from '../customers/customers.service';
import { CartService }                      from '../cart/cart.service';
import { OrganizationsClientService }       from '../organizations-client/organizations-client.service';

import { CatalogModule }                    from '../catalog/catalog.module';
import { InventoryModule }                  from '../inventory/inventory.module';
import { OrdersModule }                     from '../orders/orders.module';
import { CustomersModule }                  from '../customers/customers.module';
import { CartModule }                       from '../cart/cart.module';
import { OrganizationsClientModule }        from '../organizations-client/organizations-client.module';

@Injectable()
export class TrpcService {
  public readonly trpcMiddleware: ReturnType<typeof createExpressMiddleware>;

  constructor(
    private readonly catalog:   CatalogService,
    private readonly inventory: InventoryService,
    private readonly orders:    OrdersService,
    private readonly customers: CustomersService,
    private readonly cart:      CartService,
    private readonly orgsClient: OrganizationsClientService,
  ) {
    const appRouter = createEcommerceAppRouter({
      catalogService:   this.catalog,
      inventoryService: this.inventory,
      ordersService:    this.orders,
      customersService: this.customers,
      cartService:      this.cart,
    });

    this.trpcMiddleware = createExpressMiddleware({
      router:        appRouter,
      createContext: createTrpcContext,
      onError: ({ path, error }) => {
        console.error(`[tRPC ecommerce] ${path ?? 'unknown'}: ${error.message}`);
      },
    });
  }

  /**
   * Verifica el token Firebase e inyecta req.user.
   * Para clientes del storefront que no usen Firebase, esto es no-op.
   */
  async applyFirebaseAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.slice(7);
      try {
        const decoded = await admin.app().auth().verifyIdToken(token);
        (req as any).user = {
          uid:         decoded.uid,
          email:       decoded.email       ?? '',
          displayName: decoded.name        ?? null,
          avatarUrl:   decoded.picture     ?? null,
        };
      } catch {
        // Token inválido — adminProcedure rechazará con UNAUTHORIZED si lo requiere
      }
    }
    next();
  }

  /**
   * Resuelve TenantContext para OWNER/COLLABORATOR.
   * Reutiliza OrganizationsClientService (con cache Redis 30s).
   * Para clientes del storefront, no hay organizationId de memberships
   * así que este middleware es no-op.
   */
  async applyTenantContext(req: Request, _res: Response, next: NextFunction): Promise<void> {
    const user           = (req as any).user as { uid: string } | undefined;
    const organizationId = req.headers['x-organization-id'] as string | undefined;
    const token          = req.headers.authorization?.split(' ')[1];

    if (user?.uid && organizationId && token) {
      try {
        const access = await this.orgsClient.getAccess(token, user.uid, organizationId);
        if (access.canAccess && access.role && access.userId) {
          (req as any).tenant = {
            userId:         access.userId,
            organizationId,
            role:           access.role,
            permissions:    access.permissions ?? {},
          };
        }
      } catch {
        // Sin acceso — adminProcedure rechazará con FORBIDDEN
      }
    }
    next();
  }
}

@Module({
  imports: [
    CatalogModule,
    InventoryModule,
    OrdersModule,
    CustomersModule,
    CartModule,
    OrganizationsClientModule,
  ],
  providers: [TrpcService],
  exports:   [TrpcService],
})
export class TrpcModule implements NestModule {
  constructor(private readonly trpcService: TrpcService) {}

  configure(consumer: MiddlewareConsumer): void {
    consumer
      .apply(
        this.trpcService.applyFirebaseAuth.bind(this.trpcService),
        this.trpcService.applyTenantContext.bind(this.trpcService),
        this.trpcService.trpcMiddleware,
      )
      .forRoutes('/api/v1/trpc');
  }
}
