#!/usr/bin/env bash
# =============================================================================
# S0 — real-ecommerce-back  (Sprint 0 · bugs productivos)
# Fixes:
#   1. Race condition en checkout (overselling) — updateMany atómico con WHERE
#   2. Rate limiting en rutas @Public() — ThrottlerModule 30 req/min por IP
#   3. Helmet en main.ts
#
# Uso: ejecutar desde la raíz del repo real-ecommerce-back
# =============================================================================
set -euo pipefail

echo "▶ [real-ecommerce-back] S0 — aplicando fixes..."

# ─────────────────────────────────────────────────────────────────────────────
# 1. inventory.service.ts — reserveWithinTransaction atómico
#
# PROBLEMA ACTUAL (race condition):
#   read inventory → check available → update quantityReserved
#   Dos requests concurrentes leen el mismo stock disponible antes de que
#   cualquiera escriba → ambos pasan el check → overselling.
#
# FIX:
#   Reemplazar el patrón read-check-update por un updateMany atómico con
#   condición WHERE en la misma sentencia SQL:
#     UPDATE inventory_items
#     SET quantity_reserved = quantity_reserved + n
#     WHERE variant_id = $1
#       AND (quantity_available - quantity_reserved) >= n
#   Si count === 0 → la condición no se cumplió → stock insuficiente → 409.
#   Postgres garantiza que solo UNO de los requests concurrentes puede
#   actualizar el mismo row si ambos llegan al mismo tiempo (row-level lock).
#
# TRADE-OFF:
#   Perdemos el mensaje de error con cantidades exactas (available/requested)
#   porque no hacemos el SELECT previo. Para obtenerlo habría que hacer un
#   SELECT después del updateMany fallido — se agrega esa lectura solo en el
#   path de error (frío), no en el path feliz (caliente).
# ─────────────────────────────────────────────────────────────────────────────
cat > src/inventory/inventory.service.ts << 'EOF'
import { Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { InsufficientStockError } from './errors/insufficient-stock.error';

@Injectable()
export class InventoryService {
  constructor(private readonly prisma: PrismaService) {}

  async setStock(organizationId: string, variantId: string, quantityAvailable: number) {
    const inventory = await this.prisma.inventoryItem.findFirst({ where: { variantId, organizationId } });
    if (!inventory) throw new NotFoundException('Variante no encontrada para esta organización');

    return this.prisma.inventoryItem.update({ where: { variantId }, data: { quantityAvailable } });
  }

  /**
   * Reserva stock de forma ATÓMICA dentro de una transacción Prisma existente.
   *
   * Usa un updateMany con condición WHERE en lugar del patrón read-check-update
   * para evitar overselling bajo concurrencia. El WHERE garantiza que la
   * actualización solo ocurre si hay stock suficiente en el momento exacto
   * del write — Postgres adquiere el row lock durante el UPDATE, no durante
   * un SELECT previo.
   *
   * Si count === 0: no hubo stock suficiente. Se hace un SELECT de diagnóstico
   * (solo en el path de error) para devolver un mensaje informativo.
   */
  async reserveWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    sku: string,
    quantity: number,
  ): Promise<void> {
    const result = await tx.inventoryItem.updateMany({
      where: {
        variantId,
        // Condición atómica: solo actualiza si hay stock suficiente
        quantityAvailable: {
          gte: tx.inventoryItem.fields.quantityReserved as never,
        },
      },
      data: { quantityReserved: { increment: quantity } },
    });

    // updateMany no soporta expresiones de columna en where con Prisma ORM,
    // así que usamos $executeRaw para la condición atómica real.
    // Re-implementación con executeRaw:
    if (result.count === 0) {
      // Nunca llegaríamos acá con la implementación executeRaw de abajo,
      // pero por si acaso: diagnóstico del stock actual.
      const inventory = await tx.inventoryItem.findUnique({ where: { variantId } });
      const available = (inventory?.quantityAvailable ?? 0) - (inventory?.quantityReserved ?? 0);
      throw new InsufficientStockError(sku, quantity, available);
    }
  }

  async releaseWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    quantity: number,
  ): Promise<void> {
    await tx.inventoryItem.update({
      where: { variantId },
      data: { quantityReserved: { decrement: quantity } },
    });
  }
}
EOF

# Prisma ORM no soporta expresiones de columna en WHERE (columna >= otraColumna).
# La única forma correcta es $executeRaw. Reemplazamos el service con la
# implementación real:
cat > src/inventory/inventory.service.ts << 'EOF'
import { Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { InsufficientStockError } from './errors/insufficient-stock.error';

@Injectable()
export class InventoryService {
  constructor(private readonly prisma: PrismaService) {}

  async setStock(organizationId: string, variantId: string, quantityAvailable: number) {
    const inventory = await this.prisma.inventoryItem.findFirst({ where: { variantId, organizationId } });
    if (!inventory) throw new NotFoundException('Variante no encontrada para esta organización');

    return this.prisma.inventoryItem.update({ where: { variantId }, data: { quantityAvailable } });
  }

  /**
   * Reserva stock de forma ATÓMICA dentro de una transacción Prisma existente.
   *
   * Usa $executeRaw con una condición WHERE columna-vs-columna para evitar
   * overselling bajo concurrencia. El UPDATE adquiere el row lock en Postgres
   * y evalúa la condición de stock de forma atómica — no hay ventana de
   * tiempo entre el check y el write como en el patrón read-check-update.
   *
   * Si rowsAffected === 0: la condición no se cumplió (stock insuficiente).
   * Se hace un SELECT de diagnóstico solo en el path de error para devolver
   * un mensaje informativo sin pagar ese costo en el path feliz.
   */
  async reserveWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    sku: string,
    quantity: number,
  ): Promise<void> {
    // UPDATE atómico: solo actualiza si (quantity_available - quantity_reserved) >= quantity
    const rowsAffected = await tx.$executeRaw`
      UPDATE inventory_items
      SET    quantity_reserved = quantity_reserved + ${quantity}
      WHERE  variant_id        = ${variantId}
        AND  (quantity_available - quantity_reserved) >= ${quantity}
    `;

    if (rowsAffected === 0) {
      // Path de error (frío): leer stock actual solo para el mensaje.
      const inventory = await tx.inventoryItem.findUnique({ where: { variantId } });
      const available = (inventory?.quantityAvailable ?? 0) - (inventory?.quantityReserved ?? 0);
      throw new InsufficientStockError(sku, quantity, available);
    }
  }

  async releaseWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    quantity: number,
  ): Promise<void> {
    await tx.inventoryItem.update({
      where: { variantId },
      data: { quantityReserved: { decrement: quantity } },
    });
  }
}
EOF

echo "  ✔ src/inventory/inventory.service.ts — reserveWithinTransaction atómico (\$executeRaw)"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Instalar dependencias nuevas
# ─────────────────────────────────────────────────────────────────────────────
if ! grep -q '"@nestjs/throttler"' package.json; then
  echo "  ⚙  Instalando @nestjs/throttler..."
  pnpm add @nestjs/throttler
fi

if ! grep -q '"helmet"' package.json; then
  echo "  ⚙  Instalando helmet..."
  pnpm add helmet
fi

echo "  ✔ dependencias verificadas"

# ─────────────────────────────────────────────────────────────────────────────
# 3. app.module.ts — ThrottlerModule global (30 req/min por IP)
#
# Decisión: ThrottlerModule como APP_GUARD global. Las rutas @Public() también
# quedan bajo rate limiting porque el abuso de esas rutas es el riesgo real
# (activity, cart, checkout son las más expuestas). ThrottlerGuard va DESPUÉS
# de FirebaseAuthGuard en el array de providers — NestJS los ejecuta en orden.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/app.module.ts << 'EOF'
import { Module } from '@nestjs/common';
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

@Module({
  imports: [
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
  ],
  providers: [
    // FirebaseAuthGuard primero — si la ruta es @Public() pasa directo.
    // ThrottlerGuard segundo — limita por IP independientemente de auth.
    { provide: APP_GUARD, useClass: FirebaseAuthGuard },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
EOF

echo "  ✔ src/app.module.ts — ThrottlerModule (30 req/min por IP, global)"

# ─────────────────────────────────────────────────────────────────────────────
# 4. main.ts — agregar Helmet
#
# CORS ya está bien en ecommerce-back: si ALLOWED_ORIGINS está vacío usa
# `origin: true` (refleja el Origin del request), que con credentials: true
# es aceptable para un storefront público donde el origen es confiado.
# No se cambia el comportamiento de CORS — solo se agrega Helmet.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/main.ts << 'EOF'
import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const logger = new Logger('Bootstrap');

  app.setGlobalPrefix('api/v1');

  // ── Seguridad: Helmet ─────────────────────────────────────────────────────
  // crossOriginResourcePolicy: cross-origin permite que el storefront (origen
  // distinto) cargue recursos sin bloqueo adicional de CORP.
  app.use(
    helmet({
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );

  // ── Seguridad: CORS ───────────────────────────────────────────────────────
  // ecommerce-back sirve al storefront público — si no hay origenes explícitos
  // se refleja el Origin del request (origin: true). Distinto a real-back donde
  // el wildcard + credentials es inaceptable porque maneja tokens de identidad.
  const rawOrigins = process.env['ALLOWED_ORIGINS'] ?? '';
  const allowedOrigins = rawOrigins.split(',').map((o) => o.trim()).filter(Boolean);

  app.enableCors({
    origin: allowedOrigins.length > 0 ? allowedOrigins : true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-organization-id'],
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new ResponseInterceptor());

  const port = parseInt(process.env['PORT'] ?? '3005', 10);
  await app.listen(port, '0.0.0.0');

  logger.log(`🛍️  real-ecommerce-back en http://0.0.0.0:${port}/api/v1`);
  logger.log(`🔥 Firebase Auth SSO activo (rutas @Public() lo saltan)`);
  logger.log(`🛡️  Helmet + ThrottlerGuard (30 req/min) activos`);
}

bootstrap();
EOF

echo "  ✔ src/main.ts — Helmet agregado"

# ─────────────────────────────────────────────────────────────────────────────
# Resumen final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "✅ [real-ecommerce-back] S0 completado."
echo ""
echo "  Cambios aplicados:"
echo "  • src/inventory/inventory.service.ts"
echo "      reserveWithinTransaction usa \$executeRaw atómico"
echo "      (WHERE quantity_available - quantity_reserved >= n)"
echo "      Elimina el race condition de overselling."
echo ""
echo "  • src/app.module.ts"
echo "      ThrottlerModule: 30 req/min por IP, global."
echo "      Cubre rutas @Public(): activity, cart, checkout."
echo ""
echo "  • src/main.ts"
echo "      Helmet agregado con crossOriginResourcePolicy: cross-origin."
echo ""
echo "  ⚠  VERIFICAR antes de deployar:"
echo "     El test de concurrencia en orders.service.spec.ts pasa con el mock actual."
echo "     Para testear el fix real de concurrencia se necesita un test de integración"
echo "     contra Postgres (S4). El mock de \$executeRaw devuelve 1 por defecto."