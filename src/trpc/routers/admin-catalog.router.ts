/**
 * src/trpc/routers/admin-catalog.router.ts
 *
 * Gestión de catálogo para OWNER/COLLABORATOR del dashboard.
 *
 * Firmas reales:
 *   CatalogService.listProductsAdmin(organizationId)
 *   CatalogService.createProduct(organizationId, dto)
 *     dto: { name, handle, description?, categoryId?, status?, variants[] }
 *   CatalogService.updateProduct(organizationId, id, dto)
 *     dto: { name?, description?, categoryId?, status? }
 *
 * El catálogo PÚBLICO (listProductsPublic, getProductPublic) permanece
 * en REST con @Public() — lo consume SSG/ISR de Next.js.
 */
import { z }                                      from 'zod';
import { router, adminProcedure }                 from '../trpc';
import type { CatalogService }                    from '../../catalog/catalog.service';

const VariantInput = z.object({
  sku:      z.string().min(1),
  title:    z.string().min(1),
  priceCents: z.number().int().min(0),
  currency: z.string().default('USD'),
});

const CreateProductInput = z.object({
  name:        z.string().min(1),
  handle:      z.string().min(1),
  description: z.string().optional(),
  categoryId:  z.string().uuid().optional(),
  status:      z.enum(['DRAFT', 'PUBLISHED', 'ARCHIVED']).optional(),
  variants:    z.array(VariantInput).min(1),
});

const UpdateProductInput = z.object({
  name:        z.string().optional(),
  description: z.string().optional(),
  categoryId:  z.string().uuid().optional(),
  status:      z.enum(['DRAFT', 'PUBLISHED', 'ARCHIVED']).optional(),
});

export function createAdminCatalogRouter(catalogService: CatalogService) {
  return router({

    /**
     * adminCatalog.list
     * Todos los productos de la org (DRAFT + PUBLISHED + ARCHIVED).
     */
    list: adminProcedure.query(async ({ ctx }) => {
      return catalogService.listProductsAdmin(ctx.organizationId);
    }),

    /**
     * adminCatalog.create
     * Crea producto con variantes. OWNER o COLLABORATOR.
     */
    create: adminProcedure
      .input(CreateProductInput)
      .mutation(async ({ ctx, input }) => {
        return catalogService.createProduct(ctx.organizationId, input as any);
      }),

    /**
     * adminCatalog.update
     * Actualiza metadatos del producto. OWNER o COLLABORATOR.
     */
    update: adminProcedure
      .input(z.object({
        productId: z.string().uuid(),
        data:      UpdateProductInput,
      }))
      .mutation(async ({ ctx, input }) => {
        return catalogService.updateProduct(ctx.organizationId, input.productId, input.data as any);
      }),
  });
}
