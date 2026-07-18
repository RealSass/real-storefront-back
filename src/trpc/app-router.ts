/**
 * src/trpc/app-router.ts — realsass-ecommerce-back
 *
 * Namespaces:
 *   adminCatalog.*   → catálogo admin (OWNER/COLLABORATOR)
 *   adminInventory.* → stock admin (OWNER/COLLABORATOR)
 *   adminOrders.*    → órdenes admin (OWNER/COLLABORATOR)
 *   customer.*       → cliente del storefront autenticado
 *
 * Exporta EcommerceAppRouter como tipo para packages/trpc-contract.
 */
import { router }                          from './trpc';
import { createAdminCatalogRouter }        from './routers/admin-catalog.router';
import { createAdminInventoryRouter }      from './routers/admin-inventory.router';
import { createAdminOrdersRouter }         from './routers/admin-orders.router';
import { createCustomerRouter }            from './routers/customer.router';

import type { CatalogService }   from '../catalog/catalog.service';
import type { InventoryService } from '../inventory/inventory.service';
import type { OrdersService }    from '../orders/orders.service';
import type { CustomersService } from '../customers/customers.service';
import type { CartService }      from '../cart/cart.service';

export interface EcommerceAppRouterDeps {
  catalogService:   CatalogService;
  inventoryService: InventoryService;
  ordersService:    OrdersService;
  customersService: CustomersService;
  cartService:      CartService;
}

export function createEcommerceAppRouter(deps: EcommerceAppRouterDeps) {
  return router({
    adminCatalog:   createAdminCatalogRouter(deps.catalogService),
    adminInventory: createAdminInventoryRouter(deps.inventoryService),
    adminOrders:    createAdminOrdersRouter(deps.ordersService),
    customer:       createCustomerRouter(deps.customersService, deps.ordersService, deps.cartService),
  });
}

export type EcommerceAppRouter = ReturnType<typeof createEcommerceAppRouter>;
