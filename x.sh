#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# setup-ecommerce-back.sh
#
# Completa real-ecommerce-back (hoy un scaffold vacío de Nest) con la lógica
# de storefront: catalog, inventory, customers, activity, cart, orders.
#
# Reutiliza EXACTAMENTE el contrato de integración que ya usa real-config-back
# contra real-back (TenantRole OWNER|COLLABORATOR, CollaboratorPermissions,
# GET /auth/organization-access cacheado en Redis) — no un contrato nuevo.
#
# Ejecutar desde la raíz de real-ecommerce-back (donde está src/app.module.ts).
# No requiere Python. El prisma/schema.prisma se instala tal cual, sin
# introspección ni `prisma db pull`.
# ═══════════════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${YELLOW}▶${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

if [ ! -f "src/app.module.ts" ]; then
  fail "Correr este script desde la raíz de real-ecommerce-back (no se encontró src/app.module.ts)"
fi

log "Creando carpetas de módulos..."
mkdir -p prisma
mkdir -p src/common/{decorators,guards,types,filters,interceptors}
mkdir -p src/organizations-client/types
mkdir -p src/redis
mkdir -p src/prisma
mkdir -p src/catalog/dto
mkdir -p src/inventory/dto
mkdir -p src/inventory/errors
mkdir -p src/customers/dto
mkdir -p src/activity/dto
mkdir -p src/cart/dto
mkdir -p src/orders/dto
ok "Carpetas creadas"

# ─────────────────────────────────────────────────────────────────────────
# prisma/schema.prisma
# ─────────────────────────────────────────────────────────────────────────
log "Instalando prisma/schema.prisma..."

cat > prisma/schema.prisma << 'EOF'
// prisma/schema.prisma — real-ecommerce-back
// Ver detalle de decisiones en el mensaje que acompañó este script.
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Category {
  id             String    @id @default(uuid())
  organizationId String    @map("organization_id")
  name           String
  handle         String
  description    String?
  isActive       Boolean   @default(true) @map("is_active")
  createdAt      DateTime  @default(now()) @map("created_at")
  updatedAt      DateTime  @updatedAt @map("updated_at")
  products       Product[]

  @@unique([organizationId, handle])
  @@index([organizationId])
  @@map("categories")
}

enum ProductStatus {
  DRAFT
  PUBLISHED
  ARCHIVED
}

model Product {
  id             String        @id @default(uuid())
  organizationId String        @map("organization_id")
  categoryId     String?       @map("category_id")
  name           String
  handle         String
  description    String?
  status         ProductStatus @default(DRAFT)
  createdAt      DateTime      @default(now()) @map("created_at")
  updatedAt      DateTime      @updatedAt @map("updated_at")
  category       Category?        @relation(fields: [categoryId], references: [id])
  variants       ProductVariant[]

  @@unique([organizationId, handle])
  @@index([organizationId, status])
  @@map("products")
}

model ProductVariant {
  id             String   @id @default(uuid())
  productId      String   @map("product_id")
  organizationId String   @map("organization_id")
  sku            String
  title          String
  priceCents     Int      @map("price_cents")
  currency       String   @default("USD")
  createdAt      DateTime @default(now()) @map("created_at")
  updatedAt      DateTime @updatedAt @map("updated_at")
  product        Product         @relation(fields: [productId], references: [id], onDelete: Cascade)
  inventory      InventoryItem?
  cartItems      CartItem[]
  orderItems     OrderItem[]

  @@unique([organizationId, sku])
  @@index([productId])
  @@map("product_variants")
}

model InventoryItem {
  id                String   @id @default(uuid())
  variantId         String   @unique @map("variant_id")
  organizationId    String   @map("organization_id")
  quantityAvailable Int      @default(0) @map("quantity_available")
  quantityReserved  Int      @default(0) @map("quantity_reserved")
  updatedAt         DateTime @updatedAt @map("updated_at")
  variant           ProductVariant @relation(fields: [variantId], references: [id], onDelete: Cascade)

  @@index([organizationId])
  @@map("inventory_items")
}

model StoreCustomer {
  id             String   @id @default(uuid())
  organizationId String   @map("organization_id")
  email          String
  displayName    String?  @map("display_name")
  phone          String?
  isGuest        Boolean  @default(true) @map("is_guest")
  createdAt      DateTime @default(now()) @map("created_at")
  updatedAt      DateTime @updatedAt @map("updated_at")
  addresses      CustomerAddress[]
  carts          Cart[]
  orders         Order[]
  activityEvents CustomerActivityEvent[]

  @@unique([organizationId, email])
  @@index([organizationId])
  @@map("store_customers")
}

model CustomerAddress {
  id         String  @id @default(uuid())
  customerId String  @map("customer_id")
  label      String?
  line1      String
  line2      String?
  city       String
  province   String?
  postalCode String? @map("postal_code")
  country    String
  isDefault  Boolean @default(false) @map("is_default")
  customer   StoreCustomer @relation(fields: [customerId], references: [id], onDelete: Cascade)

  @@index([customerId])
  @@map("customer_addresses")
}

enum ActivityEventType {
  PRODUCT_VIEW
  CART_ADD
  CART_REMOVE
  CHECKOUT_STARTED
  ORDER_COMPLETED
}

model CustomerActivityEvent {
  id             String            @id @default(uuid())
  organizationId String            @map("organization_id")
  customerId     String?           @map("customer_id")
  sessionId      String            @map("session_id")
  eventType      ActivityEventType @map("event_type")
  payload        Json              @default("{}")
  createdAt      DateTime          @default(now()) @map("created_at")
  customer       StoreCustomer? @relation(fields: [customerId], references: [id])

  @@index([organizationId, createdAt])
  @@index([sessionId])
  @@map("customer_activity_events")
}

enum CartStatus {
  ACTIVE
  CONVERTED
  ABANDONED
}

model Cart {
  id             String     @id @default(uuid())
  organizationId String     @map("organization_id")
  customerId     String?    @map("customer_id")
  sessionId      String     @map("session_id")
  status         CartStatus @default(ACTIVE)
  currency       String     @default("USD")
  createdAt      DateTime   @default(now()) @map("created_at")
  updatedAt      DateTime   @updatedAt @map("updated_at")
  customer       StoreCustomer? @relation(fields: [customerId], references: [id])
  items          CartItem[]
  order          Order?

  @@index([organizationId, status])
  @@index([sessionId])
  @@index([customerId])
  @@map("carts")
}

model CartItem {
  id                     String @id @default(uuid())
  cartId                 String @map("cart_id")
  variantId              String @map("variant_id")
  quantity               Int
  unitPriceCentsSnapshot Int    @map("unit_price_cents_snapshot")
  cart                   Cart           @relation(fields: [cartId], references: [id], onDelete: Cascade)
  variant                ProductVariant @relation(fields: [variantId], references: [id])

  @@unique([cartId, variantId])
  @@map("cart_items")
}

enum OrderStatus {
  PENDING_PAYMENT
  PAID
  FULFILLING
  SHIPPED
  DELIVERED
  CANCELLED
  REFUNDED
}

model Order {
  id              String      @id @default(uuid())
  organizationId  String      @map("organization_id")
  customerId      String      @map("customer_id")
  cartId          String      @unique @map("cart_id")
  status          OrderStatus @default(PENDING_PAYMENT)
  currency        String
  subtotalCents   Int         @map("subtotal_cents")
  shippingCents   Int         @default(0) @map("shipping_cents")
  totalCents      Int         @map("total_cents")
  paymentIntentId String?     @map("payment_intent_id")
  shippingAddress Json        @map("shipping_address")
  createdAt       DateTime    @default(now()) @map("created_at")
  updatedAt       DateTime    @updatedAt @map("updated_at")
  customer        StoreCustomer      @relation(fields: [customerId], references: [id])
  cart            Cart               @relation(fields: [cartId], references: [id])
  items           OrderItem[]
  statusHistory   OrderStatusEvent[]

  @@index([organizationId, status])
  @@index([customerId])
  @@index([paymentIntentId])
  @@map("orders")
}

model OrderItem {
  id                     String @id @default(uuid())
  orderId                String @map("order_id")
  variantId              String @map("variant_id")
  quantity               Int
  unitPriceCentsSnapshot Int    @map("unit_price_cents_snapshot")
  order                  Order          @relation(fields: [orderId], references: [id], onDelete: Cascade)
  variant                ProductVariant @relation(fields: [variantId], references: [id])

  @@map("order_items")
}

model OrderStatusEvent {
  id         String       @id @default(uuid())
  orderId    String       @map("order_id")
  fromStatus OrderStatus? @map("from_status")
  toStatus   OrderStatus  @map("to_status")
  reason     String?
  createdAt  DateTime     @default(now()) @map("created_at")
  order      Order @relation(fields: [orderId], references: [id], onDelete: Cascade)

  @@index([orderId])
  @@map("order_status_events")
}
EOF
ok "schema.prisma instalado"

# ─────────────────────────────────────────────────────────────────────────
# .env.example
# ─────────────────────────────────────────────────────────────────────────
log "Generando .env.example..."
cat > .env.example << 'EOF'
NODE_ENV=development
PORT=3005

DATABASE_URL=postgresql://postgres:password@localhost:5432/real_ecommerce_db?schema=public
REDIS_URL=redis://localhost:6379

FIREBASE_PROJECT_ID=<COMPLETAR>
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@<tu-proyecto>.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

# Igual patrón que real-config-back: TenantGuard/ApiKeyGuard resuelven acceso
# contra real-back vía GET /auth/organization-access, cacheado en Redis.
ORGANIZATIONS_SERVICE_URL=http://localhost:3000
ORGANIZATIONS_SERVICE_PREFIX=/api/v1
CONFIG_CACHE_TTL_ORG_ACCESS=30

ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3002,http://localhost:3003
EOF
ok ".env.example generado"

# ─────────────────────────────────────────────────────────────────────────
# common/types — CONTRATO COMPARTIDO con real-back (copiado, no inventado)
# ─────────────────────────────────────────────────────────────────────────
log "Escribiendo contrato compartido (TenantContext)..."

cat > src/common/types/tenant-context.ts << 'EOF'
/**
 * Contrato compartido con real-back (src/users/types/organization-access.types.ts)
 * y con real-config-back (src/common/types/tenant-context.ts).
 * Si cambia en real-back, debe actualizarse acá también.
 *
 * NOTA: los nombres de permisos (canViewListings, etc.) vienen de real-back
 * y hoy están pensados para el dominio de listings. Si el modelo de permisos
 * de real-back todavía no tiene granularidad por producto ("storefront"),
 * usá este mismo objeto (ya sirve para distinguir OWNER de COLLABORATOR) y
 * date por avisado: esto es candidato a ADR apenas real-back exponga
 * permissions específicos para e-commerce.
 */

export type TenantRole = 'OWNER' | 'COLLABORATOR';

export interface CollaboratorPermissions {
  canViewListings: boolean;
  canCreateListings: boolean;
  canEditListings: boolean;
  canDeleteListings: boolean;
  canViewStats: boolean;
  canManageLeads: boolean;
  canManageCollaborators: boolean;
}

export const FULL_PERMISSIONS: CollaboratorPermissions = {
  canViewListings: true,
  canCreateListings: true,
  canEditListings: true,
  canDeleteListings: true,
  canViewStats: true,
  canManageLeads: true,
  canManageCollaborators: true,
};

export interface TenantContext {
  userId: string;
  organizationId: string;
  role: TenantRole;
  permissions: CollaboratorPermissions;
  apiKeyScopes?: string[];
}
EOF
ok "tenant-context.ts escrito"

# ─────────────────────────────────────────────────────────────────────────
# common/decorators
# ─────────────────────────────────────────────────────────────────────────
log "Generando decorators..."

cat > src/common/decorators/public.decorator.ts << 'EOF'
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
EOF

cat > src/common/decorators/tenant.decorator.ts << 'EOF'
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { TenantContext } from '../types/tenant-context';

export const Tenant = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): TenantContext =>
    ctx.switchToHttp().getRequest().tenant,
);
EOF

cat > src/common/decorators/current-user.decorator.ts << 'EOF'
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export interface CurrentUserPayload {
  uid: string;
  email: string;
  displayName: string | null;
  avatarUrl: string | null;
}

export const CurrentUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): CurrentUserPayload =>
    ctx.switchToHttp().getRequest().user,
);
EOF

cat > src/common/decorators/roles.decorator.ts << 'EOF'
import { SetMetadata } from '@nestjs/common';
import type { TenantRole } from '../types/tenant-context';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: TenantRole[]) => SetMetadata(ROLES_KEY, roles);
EOF
ok "Decorators generados"

# ─────────────────────────────────────────────────────────────────────────
# common/guards — mismo patrón que real-config-back
# ─────────────────────────────────────────────────────────────────────────
log "Generando guards (Firebase, Tenant, Roles)..."

cat > src/common/guards/firebase-auth.guard.ts << 'EOF'
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import * as admin from 'firebase-admin';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (isPublic) return true;

    const req = ctx.switchToHttp().getRequest();
    const token = this.extractToken(req);
    if (!token) throw new UnauthorizedException('Token de autenticación requerido');

    try {
      const decoded = await admin.app().auth().verifyIdToken(token);
      req.user = {
        uid: decoded.uid,
        email: decoded.email ?? '',
        displayName: decoded.name ?? null,
        avatarUrl: decoded.picture ?? null,
      };
      return true;
    } catch {
      throw new UnauthorizedException('Token inválido o expirado');
    }
  }

  private extractToken(req: { headers: Record<string, string | undefined> }): string | undefined {
    const [type, token] = req.headers.authorization?.split(' ') ?? [];
    return type === 'Bearer' ? token : undefined;
  }
}
EOF

cat > src/common/guards/tenant.guard.ts << 'EOF'
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { OrganizationsClientService } from '../../organizations-client/organizations-client.service';
import type { TenantContext } from '../types/tenant-context';

/**
 * Resuelve el TenantContext consultando a real-back vía
 * OrganizationsClientService — mismo patrón que real-config-back.
 * Este servicio NO tiene tabla local de users/memberships.
 */
@Injectable()
export class TenantGuard implements CanActivate {
  constructor(private readonly orgsClient: OrganizationsClientService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest();
    const user = req.user as { uid: string } | undefined;
    const organizationId = req.headers['x-organization-id'] as string | undefined;
    const token = this.extractToken(req);

    if (!organizationId) throw new ForbiddenException('Header x-organization-id requerido');
    if (!user?.uid) throw new UnauthorizedException('Usuario no autenticado');
    if (!token) throw new UnauthorizedException('Token de autenticación requerido');

    const access = await this.orgsClient.getAccess(token, user.uid, organizationId);

    if (!access.canAccess || !access.role || !access.permissions || !access.userId) {
      throw new ForbiddenException(access.reason ?? 'No tenés acceso a esta organización');
    }

    const tenantCtx: TenantContext = {
      userId: access.userId,
      organizationId,
      role: access.role,
      permissions: access.permissions,
    };
    req.tenant = tenantCtx;
    return true;
  }

  private extractToken(req: { headers: Record<string, string | undefined> }): string | undefined {
    const [type, token] = req.headers.authorization?.split(' ') ?? [];
    return type === 'Bearer' ? token : undefined;
  }
}
EOF

cat > src/common/guards/roles.guard.ts << 'EOF'
import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { TenantContext, TenantRole } from '../types/tenant-context';
import { ROLES_KEY } from '../decorators/roles.decorator';

const HIERARCHY: Record<TenantRole, number> = { OWNER: 2, COLLABORATOR: 1 };

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<TenantRole[]>(ROLES_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!required?.length) return true;

    const { tenant } = ctx.switchToHttp().getRequest() as { tenant?: TenantContext };
    if (!tenant) throw new ForbiddenException('Tenant context requerido');

    const userLevel = HIERARCHY[tenant.role] ?? 0;
    const minLevel = Math.min(...required.map((r) => HIERARCHY[r] ?? 0));

    if (userLevel < minLevel) {
      throw new ForbiddenException(`Rol requerido: ${required.join(' o ')}. Tu rol: ${tenant.role}`);
    }
    return true;
  }
}
EOF
ok "Guards generados"

# ─────────────────────────────────────────────────────────────────────────
# common/filters + interceptors — envelope { success, data }
# ─────────────────────────────────────────────────────────────────────────
log "Generando filter e interceptor de respuesta..."

cat > src/common/filters/http-exception.filter.ts << 'EOF'
import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { Response, Request } from 'express';

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const status = exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;
    const body = exception instanceof HttpException ? exception.getResponse() : null;

    const message =
      typeof body === 'object' && body !== null && 'message' in body
        ? (body as { message: string | string[] }).message
        : exception instanceof Error
          ? exception.message
          : 'Error interno';

    const errors = typeof body === 'object' && body !== null && Array.isArray((body as any).message)
      ? (body as any).message
      : undefined;

    if (status >= 500) {
      this.logger.error(exception instanceof Error ? exception.message : 'Error desconocido', exception instanceof Error ? exception.stack : undefined);
    }

    response.status(status).json({
      success: false,
      statusCode: status,
      message,
      ...(errors && { errors }),
      timestamp: new Date().toISOString(),
      path: request.url,
    });
  }
}
EOF

cat > src/common/interceptors/response.interceptor.ts << 'EOF'
import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, unknown> {
  intercept(_ctx: ExecutionContext, next: CallHandler<T>): Observable<unknown> {
    return next.handle().pipe(map((data) => ({ success: true, data })));
  }
}
EOF
ok "Filter e interceptor generados"

# ─────────────────────────────────────────────────────────────────────────
# redis/ — igual que real-config-back
# ─────────────────────────────────────────────────────────────────────────
log "Generando RedisService..."

cat > src/redis/redis.service.ts << 'EOF'
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private client!: Redis;

  onModuleInit(): void {
    this.client = new Redis(process.env['REDIS_URL'] ?? 'redis://localhost:6379');
    this.client.on('error', (err) => this.logger.error('Redis error', err));
  }

  async onModuleDestroy(): Promise<void> {
    await this.client?.quit();
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.client.set(key, value, 'EX', ttlSeconds);
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }
}
EOF

cat > src/redis/redis.module.ts << 'EOF'
import { Global, Module } from '@nestjs/common';
import { RedisService } from './redis.service';

@Global()
@Module({
  providers: [RedisService],
  exports: [RedisService],
})
export class RedisModule {}
EOF
ok "RedisModule generado"

# ─────────────────────────────────────────────────────────────────────────
# organizations-client/ — cliente system-to-system contra real-back
# ─────────────────────────────────────────────────────────────────────────
log "Generando OrganizationsClientService..."

cat > src/organizations-client/types/organization-access.types.ts << 'EOF'
/**
 * Contrato compartido con real-back (src/users/types/organization-access.types.ts)
 * y con real-config-back. Si cambia uno, actualizar los tres.
 */
import type { TenantRole, CollaboratorPermissions } from '../../common/types/tenant-context';

export type { TenantRole, CollaboratorPermissions };

export interface OrganizationAccessResult {
  canAccess: boolean;
  userId?: string;
  organizationId?: string;
  role?: TenantRole;
  permissions?: CollaboratorPermissions;
  reason?: string;
}
EOF

cat > src/organizations-client/organizations-client.service.ts << 'EOF'
import {
  ForbiddenException,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { RedisService } from '../redis/redis.service';
import type { OrganizationAccessResult } from './types/organization-access.types';

const CACHE_TTL_SECONDS = Number(process.env['CONFIG_CACHE_TTL_ORG_ACCESS'] ?? 30);
const REQUEST_TIMEOUT_MS = 5000;

// real-back tiene setGlobalPrefix('api/v1') — ver src/main.ts de real-back.
const ORGANIZATIONS_SERVICE_PREFIX = process.env['ORGANIZATIONS_SERVICE_PREFIX'] ?? '/api/v1';

/**
 * Cliente HTTP hacia real-back — única fuente de verdad de usuarios,
 * organizaciones, colaboradores y permisos. Resuelve { role, permissions }
 * para (usuario autenticado, organización activa) vía
 * GET /auth/organization-access, cacheado en Redis con TTL corto.
 *
 * Mismo servicio, palabra por palabra, que usa real-config-back — así
 * cualquiera que ya conozca ese microservicio reconoce este al toque.
 */
@Injectable()
export class OrganizationsClientService {
  private readonly logger = new Logger(OrganizationsClientService.name);
  private readonly baseUrl: string;

  constructor(private readonly redis: RedisService) {
    this.baseUrl = (process.env['ORGANIZATIONS_SERVICE_URL'] ?? 'http://localhost:3000').replace(/\/+$/, '');
  }

  private cacheKey(firebaseUid: string, organizationId: string): string {
    return `org-access:${firebaseUid}:${organizationId}`;
  }

  async getAccess(
    firebaseToken: string,
    firebaseUid: string,
    organizationId: string,
  ): Promise<OrganizationAccessResult> {
    const key = this.cacheKey(firebaseUid, organizationId);

    const cached = await this.redis.get(key).catch(() => null);
    if (cached) {
      return JSON.parse(cached) as OrganizationAccessResult;
    }

    const result = await this.fetchFromOrganizationsService(firebaseToken, organizationId);

    if (result.canAccess) {
      await this.redis.set(key, JSON.stringify(result), CACHE_TTL_SECONDS).catch(() => undefined);
    }

    return result;
  }

  private async fetchFromOrganizationsService(
    firebaseToken: string,
    organizationId: string,
  ): Promise<OrganizationAccessResult> {
    const url = `${this.baseUrl}${ORGANIZATIONS_SERVICE_PREFIX}/auth/organization-access?organizationId=${encodeURIComponent(organizationId)}`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${firebaseToken}` },
        signal: controller.signal,
      });

      if (response.status === 401) {
        throw new UnauthorizedException('Token rechazado por real-back');
      }
      if (!response.ok) {
        throw new ForbiddenException(`real-back respondió ${response.status} para organizationId=${organizationId}`);
      }

      const body = (await response.json()) as { data: OrganizationAccessResult };
      return body.data;
    } catch (error) {
      if (error instanceof UnauthorizedException || error instanceof ForbiddenException) throw error;
      this.logger.error('No se pudo contactar a real-back', error as Error);
      throw new ServiceUnavailableException('Servicio de identidad no disponible temporalmente');
    } finally {
      clearTimeout(timeout);
    }
  }
}
EOF

cat > src/organizations-client/organizations-client.module.ts << 'EOF'
import { Global, Module } from '@nestjs/common';
import { RedisModule } from '../redis/redis.module';
import { OrganizationsClientService } from './organizations-client.service';

@Global()
@Module({
  imports: [RedisModule],
  providers: [OrganizationsClientService],
  exports: [OrganizationsClientService],
})
export class OrganizationsClientModule {}
EOF
ok "OrganizationsClientModule generado"

# ─────────────────────────────────────────────────────────────────────────
# prisma/ (servicio Nest, no confundir con prisma/schema.prisma)
# ─────────────────────────────────────────────────────────────────────────
log "Generando PrismaService..."

cat > src/prisma/prisma.service.ts << 'EOF'
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  async onModuleInit(): Promise<void> {
    await this.$connect();
    this.logger.log('Conectado a la base de datos de real-ecommerce-back');
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
EOF

cat > src/prisma/prisma.module.ts << 'EOF'
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
EOF
ok "PrismaModule generado"

# ─────────────────────────────────────────────────────────────────────────
# catalog/ — admin CRUD + lectura pública
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo catalog..."

cat > src/catalog/dto/create-product.dto.ts << 'EOF'
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Min, ValidateNested } from 'class-validator';

class CreateVariantDto {
  @IsString() sku!: string;
  @IsString() title!: string;
  @IsInt() @Min(0) priceCents!: number;
  @IsOptional() @IsString() currency?: string;
}

export class CreateProductDto {
  @IsString() name!: string;
  @IsString() handle!: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() categoryId?: string;
  @IsOptional() @IsIn(['DRAFT', 'PUBLISHED', 'ARCHIVED']) status?: string;

  @ValidateNested({ each: true })
  @Type(() => CreateVariantDto)
  variants!: CreateVariantDto[];
}
EOF

cat > src/catalog/dto/update-product.dto.ts << 'EOF'
import { IsIn, IsOptional, IsString } from 'class-validator';

export class UpdateProductDto {
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() categoryId?: string;
  @IsOptional() @IsIn(['DRAFT', 'PUBLISHED', 'ARCHIVED']) status?: string;
}
EOF

cat > src/catalog/catalog.service.ts << 'EOF'
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

@Injectable()
export class CatalogService {
  constructor(private readonly prisma: PrismaService) {}

  // ── Admin ────────────────────────────────────────────────────────────
  async createProduct(organizationId: string, dto: CreateProductDto) {
    return this.prisma.product.create({
      data: {
        organizationId,
        name: dto.name,
        handle: dto.handle,
        description: dto.description,
        categoryId: dto.categoryId,
        status: (dto.status as any) ?? 'DRAFT',
        variants: {
          create: dto.variants.map((v) => ({
            organizationId,
            sku: v.sku,
            title: v.title,
            priceCents: v.priceCents,
            currency: v.currency ?? 'USD',
            inventory: { create: { organizationId, quantityAvailable: 0 } },
          })),
        },
      },
      include: { variants: { include: { inventory: true } } },
    });
  }

  async listProductsAdmin(organizationId: string) {
    return this.prisma.product.findMany({
      where: { organizationId },
      include: { variants: { include: { inventory: true } }, category: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updateProduct(organizationId: string, productId: string, dto: UpdateProductDto) {
    const product = await this.prisma.product.findFirst({ where: { id: productId, organizationId } });
    if (!product) throw new NotFoundException('Producto no encontrado');

    return this.prisma.product.update({
      where: { id: productId },
      data: { ...dto, status: (dto.status as any) ?? undefined },
    });
  }

  // ── Público (storefront) ─────────────────────────────────────────────
  async listProductsPublic(organizationId: string, categoryHandle?: string) {
    return this.prisma.product.findMany({
      where: {
        organizationId,
        status: 'PUBLISHED',
        ...(categoryHandle && { category: { handle: categoryHandle } }),
      },
      include: { variants: { include: { inventory: true } }, category: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getProductPublic(organizationId: string, handle: string) {
    const product = await this.prisma.product.findFirst({
      where: { organizationId, handle, status: 'PUBLISHED' },
      include: { variants: { include: { inventory: true } }, category: true },
    });
    if (!product) throw new NotFoundException('Producto no encontrado o no publicado');
    return product;
  }
}
EOF

cat > src/catalog/catalog.controller.ts << 'EOF'
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
EOF

cat > src/catalog/public-catalog.controller.ts << 'EOF'
import { Controller, Get, Param, Query } from '@nestjs/common';
import { CatalogService } from './catalog.service';
import { Public } from '../common/decorators/public.decorator';

// Público — visitantes anónimos de la tienda. Sin Firebase.
// TODO: cuando exista StorefrontSettings, validar acá que la organización
// tenga el storefront publicado antes de exponer el catálogo.
@Controller('ecommerce/public/:organizationId/products')
@Public()
export class PublicCatalogController {
  constructor(private readonly catalogService: CatalogService) {}

  @Get()
  list(@Param('organizationId') organizationId: string, @Query('category') category?: string) {
    return this.catalogService.listProductsPublic(organizationId, category);
  }

  @Get(':handle')
  get(@Param('organizationId') organizationId: string, @Param('handle') handle: string) {
    return this.catalogService.getProductPublic(organizationId, handle);
  }
}
EOF

cat > src/catalog/catalog.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { CatalogService } from './catalog.service';
import { CatalogController } from './catalog.controller';
import { PublicCatalogController } from './public-catalog.controller';

@Module({
  controllers: [CatalogController, PublicCatalogController],
  providers: [CatalogService],
  exports: [CatalogService],
})
export class CatalogModule {}
EOF
ok "Módulo catalog generado"

# ─────────────────────────────────────────────────────────────────────────
# inventory/ — fuente única de stock
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo inventory..."

cat > src/inventory/dto/update-stock.dto.ts << 'EOF'
import { IsInt, Min } from 'class-validator';

export class UpdateStockDto {
  @IsInt() @Min(0) quantityAvailable!: number;
}
EOF

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
   * Reserva stock dentro de una transacción Prisma existente (tx). Se usa
   * desde el checkout — nunca se llama fuera de una transacción, para
   * evitar overselling bajo concurrencia.
   */
  async reserveWithinTransaction(
    tx: Prisma.TransactionClient,
    variantId: string,
    sku: string,
    quantity: number,
  ): Promise<void> {
    const inventory = await tx.inventoryItem.findUnique({ where: { variantId } });
    const available = (inventory?.quantityAvailable ?? 0) - (inventory?.quantityReserved ?? 0);

    if (available < quantity) {
      throw new InsufficientStockError(sku, quantity, available);
    }

    await tx.inventoryItem.update({
      where: { variantId },
      data: { quantityReserved: { increment: quantity } },
    });
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

cat > src/inventory/errors/insufficient-stock.error.ts << 'EOF'
import { ConflictException } from '@nestjs/common';

export class InsufficientStockError extends ConflictException {
  constructor(sku: string, requested: number, available: number) {
    super(`Stock insuficiente para SKU ${sku}: pedidos ${requested}, disponibles ${available}`);
  }
}
EOF

cat > src/inventory/inventory.controller.ts << 'EOF'
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
EOF

cat > src/inventory/inventory.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { InventoryController } from './inventory.controller';

@Module({
  controllers: [InventoryController],
  providers: [InventoryService],
  exports: [InventoryService],
})
export class InventoryModule {}
EOF
ok "Módulo inventory generado"

# ─────────────────────────────────────────────────────────────────────────
# customers/ — identidad del cliente final + adopción de carrito
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo customers..."

cat > src/customers/dto/identify-customer.dto.ts << 'EOF'
import { IsEmail, IsOptional, IsString } from 'class-validator';

export class IdentifyCustomerDto {
  @IsEmail() email!: string;
  @IsOptional() @IsString() displayName?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() cartId?: string;
}
EOF

cat > src/customers/customers.service.ts << 'EOF'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Identifica (o crea) al cliente por email, scoped a la organización, y
   * si viene cartId, adopta ese carrito anónimo al cliente recién
   * identificado — el carrito no se pierde al pasar de anónimo a conocido.
   */
  async identify(organizationId: string, email: string, displayName?: string, phone?: string, cartId?: string) {
    const customer = await this.prisma.storeCustomer.upsert({
      where: { organizationId_email: { organizationId, email } },
      update: { displayName, phone },
      create: { organizationId, email, displayName, phone, isGuest: true },
    });

    if (cartId) {
      await this.prisma.cart.updateMany({
        where: { id: cartId, organizationId, status: 'ACTIVE' },
        data: { customerId: customer.id },
      });
    }

    return customer;
  }

  async findById(organizationId: string, customerId: string) {
    return this.prisma.storeCustomer.findFirst({ where: { id: customerId, organizationId } });
  }
}
EOF

cat > src/customers/customers.controller.ts << 'EOF'
import { Body, Controller, Param, Post } from '@nestjs/common';
import { CustomersService } from './customers.service';
import { IdentifyCustomerDto } from './dto/identify-customer.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/customers')
@Public()
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Post('identify')
  identify(@Param('organizationId') organizationId: string, @Body() dto: IdentifyCustomerDto) {
    return this.customersService.identify(organizationId, dto.email, dto.displayName, dto.phone, dto.cartId);
  }
}
EOF

cat > src/customers/customers.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { CustomersService } from './customers.service';
import { CustomersController } from './customers.controller';

@Module({
  controllers: [CustomersController],
  providers: [CustomersService],
  exports: [CustomersService],
})
export class CustomersModule {}
EOF
ok "Módulo customers generado"

# ─────────────────────────────────────────────────────────────────────────
# activity/ — log append-only
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo activity..."

cat > src/activity/dto/log-event.dto.ts << 'EOF'
import { IsIn, IsObject, IsOptional, IsString } from 'class-validator';

export class LogEventDto {
  @IsString() sessionId!: string;
  @IsIn(['PRODUCT_VIEW', 'CART_ADD', 'CART_REMOVE', 'CHECKOUT_STARTED', 'ORDER_COMPLETED'])
  eventType!: string;
  @IsOptional() @IsString() customerId?: string;
  @IsOptional() @IsObject() payload?: Record<string, unknown>;
}
EOF

cat > src/activity/activity.service.ts << 'EOF'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ActivityService {
  constructor(private readonly prisma: PrismaService) {}

  // Append-only — no hay update ni delete. Errores acá no deben tumbar el
  // flujo de compra: quien llama debe tratar esto como best-effort.
  async log(
    organizationId: string,
    sessionId: string,
    eventType: string,
    customerId?: string,
    payload: Record<string, unknown> = {},
  ) {
    return this.prisma.customerActivityEvent.create({
      data: { organizationId, sessionId, eventType: eventType as any, customerId, payload },
    });
  }
}
EOF

cat > src/activity/activity.controller.ts << 'EOF'
import { Body, Controller, Param, Post } from '@nestjs/common';
import { ActivityService } from './activity.service';
import { LogEventDto } from './dto/log-event.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/activity')
@Public()
export class ActivityController {
  constructor(private readonly activityService: ActivityService) {}

  @Post()
  log(@Param('organizationId') organizationId: string, @Body() dto: LogEventDto) {
    return this.activityService.log(organizationId, dto.sessionId, dto.eventType, dto.customerId, dto.payload);
  }
}
EOF

cat > src/activity/activity.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { ActivityService } from './activity.service';
import { ActivityController } from './activity.controller';

@Module({
  controllers: [ActivityController],
  providers: [ActivityService],
  exports: [ActivityService],
})
export class ActivityModule {}
EOF
ok "Módulo activity generado"

# ─────────────────────────────────────────────────────────────────────────
# cart/ — puede empezar anónimo
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo cart..."

cat > src/cart/dto/add-item.dto.ts << 'EOF'
import { IsInt, IsOptional, IsString, Min } from 'class-validator';

export class AddItemDto {
  @IsString() sessionId!: string;
  @IsOptional() @IsString() cartId?: string;
  @IsString() variantId!: string;
  @IsInt() @Min(1) quantity!: number;
}
EOF

cat > src/cart/cart.service.ts << 'EOF'
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ActivityService } from '../activity/activity.service';

@Injectable()
export class CartService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityService: ActivityService,
  ) {}

  private async getOrCreateActiveCart(organizationId: string, sessionId: string, cartId?: string) {
    if (cartId) {
      const existing = await this.prisma.cart.findFirst({ where: { id: cartId, organizationId, status: 'ACTIVE' } });
      if (existing) return existing;
    }

    return this.prisma.cart.create({
      data: { organizationId, sessionId, status: 'ACTIVE', currency: 'USD' },
    });
  }

  async addItem(organizationId: string, sessionId: string, variantId: string, quantity: number, cartId?: string) {
    const variant = await this.prisma.productVariant.findFirst({ where: { id: variantId, organizationId } });
    if (!variant) throw new NotFoundException('Variante no encontrada');

    const cart = await this.getOrCreateActiveCart(organizationId, sessionId, cartId);

    const item = await this.prisma.cartItem.upsert({
      where: { cartId_variantId: { cartId: cart.id, variantId } },
      update: { quantity: { increment: quantity } },
      create: {
        cartId: cart.id,
        variantId,
        quantity,
        unitPriceCentsSnapshot: variant.priceCents,
      },
    });

    await this.activityService
      .log(organizationId, sessionId, 'CART_ADD', cart.customerId ?? undefined, { variantId, quantity })
      .catch(() => undefined);

    return this.getCart(organizationId, cart.id);
  }

  async removeItem(organizationId: string, cartId: string, variantId: string) {
    const cart = await this.prisma.cart.findFirst({ where: { id: cartId, organizationId } });
    if (!cart) throw new NotFoundException('Carrito no encontrado');

    await this.prisma.cartItem.deleteMany({ where: { cartId, variantId } });
    return this.getCart(organizationId, cartId);
  }

  async getCart(organizationId: string, cartId: string) {
    const cart = await this.prisma.cart.findFirst({
      where: { id: cartId, organizationId },
      include: { items: { include: { variant: true } } },
    });
    if (!cart) throw new NotFoundException('Carrito no encontrado');
    return cart;
  }
}
EOF

cat > src/cart/cart.controller.ts << 'EOF'
import { Body, Controller, Delete, Get, Param, Post } from '@nestjs/common';
import { CartService } from './cart.service';
import { AddItemDto } from './dto/add-item.dto';
import { Public } from '../common/decorators/public.decorator';

@Controller('ecommerce/public/:organizationId/cart')
@Public()
export class CartController {
  constructor(private readonly cartService: CartService) {}

  @Post('items')
  addItem(@Param('organizationId') organizationId: string, @Body() dto: AddItemDto) {
    return this.cartService.addItem(organizationId, dto.sessionId, dto.variantId, dto.quantity, dto.cartId);
  }

  @Delete(':cartId/items/:variantId')
  removeItem(
    @Param('organizationId') organizationId: string,
    @Param('cartId') cartId: string,
    @Param('variantId') variantId: string,
  ) {
    return this.cartService.removeItem(organizationId, cartId, variantId);
  }

  @Get(':cartId')
  get(@Param('organizationId') organizationId: string, @Param('cartId') cartId: string) {
    return this.cartService.getCart(organizationId, cartId);
  }
}
EOF

cat > src/cart/cart.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { CartService } from './cart.service';
import { CartController } from './cart.controller';
import { ActivityModule } from '../activity/activity.module';

@Module({
  imports: [ActivityModule],
  controllers: [CartController],
  providers: [CartService],
  exports: [CartService],
})
export class CartModule {}
EOF
ok "Módulo cart generado"

# ─────────────────────────────────────────────────────────────────────────
# orders/ — checkout transaccional (sin cobro real todavía)
# ─────────────────────────────────────────────────────────────────────────
log "Generando módulo orders (checkout)..."

cat > src/orders/dto/checkout.dto.ts << 'EOF'
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Min, ValidateNested } from 'class-validator';

class ShippingAddressDto {
  @IsString() line1!: string;
  @IsOptional() @IsString() line2?: string;
  @IsString() city!: string;
  @IsOptional() @IsString() province?: string;
  @IsOptional() @IsString() postalCode?: string;
  @IsString() country!: string;
}

export class CheckoutDto {
  @IsString() cartId!: string;
  @IsString() customerId!: string;

  @ValidateNested()
  @Type(() => ShippingAddressDto)
  shippingAddress!: ShippingAddressDto;

  @IsOptional() @IsInt() @Min(0) shippingCents?: number;
}
EOF

cat > src/orders/orders.service.ts << 'EOF'
import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { InventoryService } from '../inventory/inventory.service';
import { ActivityService } from '../activity/activity.service';
import { CheckoutDto } from './dto/checkout.dto';

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly inventoryService: InventoryService,
    private readonly activityService: ActivityService,
  ) {}

  /**
   * Convierte un carrito ACTIVE en una orden PENDING_PAYMENT. Reserva de
   * stock y creación de orden van en UNA transacción — evita overselling
   * bajo concurrencia. El cobro real (pasarela-pagos) se conecta después:
   * paymentIntentId queda null hasta ese momento.
   */
  async checkout(organizationId: string, dto: CheckoutDto) {
    const cart = await this.prisma.cart.findFirst({
      where: { id: dto.cartId, organizationId },
      include: { items: { include: { variant: true } } },
    });
    if (!cart) throw new NotFoundException('Carrito no encontrado');
    if (cart.status !== 'ACTIVE') throw new ConflictException(`El carrito ${cart.id} ya no está activo`);
    if (cart.items.length === 0) throw new BadRequestException('El carrito está vacío');

    const customer = await this.prisma.storeCustomer.findFirst({
      where: { id: dto.customerId, organizationId },
    });
    if (!customer) throw new NotFoundException('Cliente no encontrado');

    const shippingCents = dto.shippingCents ?? 0;
    const subtotalCents = cart.items.reduce((sum, item) => sum + item.unitPriceCentsSnapshot * item.quantity, 0);
    const totalCents = subtotalCents + shippingCents;

    const order = await this.prisma.$transaction(async (tx) => {
      for (const item of cart.items) {
        await this.inventoryService.reserveWithinTransaction(tx, item.variantId, item.variant.sku, item.quantity);
      }

      const created = await tx.order.create({
        data: {
          organizationId,
          customerId: customer.id,
          cartId: cart.id,
          currency: cart.currency,
          subtotalCents,
          shippingCents,
          totalCents,
          shippingAddress: dto.shippingAddress as any,
          items: {
            create: cart.items.map((item) => ({
              variantId: item.variantId,
              quantity: item.quantity,
              unitPriceCentsSnapshot: item.unitPriceCentsSnapshot,
            })),
          },
          statusHistory: { create: { toStatus: 'PENDING_PAYMENT', reason: 'Orden creada desde carrito' } },
        },
      });

      await tx.cart.update({ where: { id: cart.id }, data: { status: 'CONVERTED' } });

      return created;
    });

    await this.activityService
      .log(organizationId, cart.sessionId, 'ORDER_COMPLETED', customer.id, { orderId: order.id })
      .catch(() => undefined);

    // TODO: cuando se conecte pasarela-pagos, acá se crea el PaymentIntent
    // y se guarda paymentIntentId. Hoy la orden queda en PENDING_PAYMENT.
    return order;
  }

  async listOrders(organizationId: string) {
    return this.prisma.order.findMany({
      where: { organizationId },
      include: { items: true, customer: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getOrder(organizationId: string, orderId: string) {
    const order = await this.prisma.order.findFirst({
      where: { id: orderId, organizationId },
      include: { items: { include: { variant: true } }, customer: true, statusHistory: true },
    });
    if (!order) throw new NotFoundException('Orden no encontrada');
    return order;
  }
}
EOF

cat > src/orders/orders.controller.ts << 'EOF'
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
EOF

cat > src/orders/checkout.controller.ts << 'EOF'
import { Body, Controller, Param, Post } from '@nestjs/common';
import { OrdersService } from './orders.service';
import { CheckoutDto } from './dto/checkout.dto';
import { Public } from '../common/decorators/public.decorator';

// Público — el cliente final finaliza la compra. Sin Firebase.
@Controller('ecommerce/public/:organizationId/checkout')
@Public()
export class CheckoutController {
  constructor(private readonly ordersService: OrdersService) {}

  @Post()
  checkout(@Param('organizationId') organizationId: string, @Body() dto: CheckoutDto) {
    return this.ordersService.checkout(organizationId, dto);
  }
}
EOF

cat > src/orders/orders.module.ts << 'EOF'
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
EOF
ok "Módulo orders generado"

# ─────────────────────────────────────────────────────────────────────────
# app.module.ts + main.ts
# ─────────────────────────────────────────────────────────────────────────
log "Reescribiendo app.module.ts y main.ts..."

cat > src/app.module.ts << 'EOF'
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
EOF

cat > src/main.ts << 'EOF'
import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const logger = new Logger('Bootstrap');

  app.setGlobalPrefix('api/v1');

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
}

bootstrap();
EOF
ok "app.module.ts y main.ts actualizados"

# ─────────────────────────────────────────────────────────────────────────
# Tests — unit del checkout (stock insuficiente / feliz)
# ─────────────────────────────────────────────────────────────────────────
log "Generando tests unitarios de orders.service..."

cat > src/orders/orders.service.spec.ts << 'EOF'
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { OrdersService } from './orders.service';

describe('OrdersService.checkout', () => {
  const buildDeps = (overrides: Partial<any> = {}) => {
    const prisma = {
      cart: {
        findFirst: jest.fn(),
        update: jest.fn(),
      },
      storeCustomer: { findFirst: jest.fn() },
      $transaction: jest.fn(async (fn: any) => fn(prisma)),
      order: { create: jest.fn() },
      ...overrides.prisma,
    };
    const inventoryService = { reserveWithinTransaction: jest.fn(), ...overrides.inventoryService };
    const activityService = { log: jest.fn().mockResolvedValue(undefined), ...overrides.activityService };

    return { prisma, inventoryService, activityService };
  };

  it('lanza NotFoundException si el carrito no existe', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue(null);
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-x', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(NotFoundException);
  });

  it('lanza ConflictException si el carrito ya no está ACTIVE', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({ id: 'cart-1', status: 'CONVERTED', items: [] });
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-1', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(ConflictException);
  });

  it('lanza BadRequestException si el carrito está vacío', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({ id: 'cart-1', status: 'ACTIVE', items: [] });
    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    await expect(
      service.checkout('org-1', { cartId: 'cart-1', customerId: 'cust-1', shippingAddress: {} as any }),
    ).rejects.toThrow(BadRequestException);
  });

  it('crea la orden y marca el carrito CONVERTED en el camino feliz', async () => {
    const { prisma, inventoryService, activityService } = buildDeps();
    prisma.cart.findFirst.mockResolvedValue({
      id: 'cart-1',
      status: 'ACTIVE',
      currency: 'USD',
      sessionId: 'sess-1',
      items: [
        { variantId: 'v1', quantity: 2, unitPriceCentsSnapshot: 1000, variant: { sku: 'SKU-1' } },
      ],
    });
    prisma.storeCustomer.findFirst.mockResolvedValue({ id: 'cust-1' });
    prisma.order.create.mockResolvedValue({ id: 'order-1', totalCents: 2000 });

    const service = new OrdersService(prisma as any, inventoryService as any, activityService as any);

    const result = await service.checkout('org-1', {
      cartId: 'cart-1',
      customerId: 'cust-1',
      shippingAddress: { line1: 'Calle 123', city: 'Catamarca', country: 'AR' } as any,
    });

    expect(inventoryService.reserveWithinTransaction).toHaveBeenCalledWith(prisma, 'v1', 'SKU-1', 2);
    expect(prisma.cart.update).toHaveBeenCalledWith({ where: { id: 'cart-1' }, data: { status: 'CONVERTED' } });
    expect(result).toEqual({ id: 'order-1', totalCents: 2000 });
  });
});
EOF
ok "Tests generados"

# ─────────────────────────────────────────────────────────────────────────
# package.json — agregar dependencias necesarias
# ─────────────────────────────────────────────────────────────────────────
log "Actualizando package.json con dependencias nuevas..."

node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies = {
  ...pkg.dependencies,
  '@prisma/client': '^5.20.0',
  'class-transformer': '^0.5.1',
  'class-validator': '^0.14.1',
  'firebase-admin': '^12.4.0',
  'ioredis': '^5.4.1',
};
pkg.devDependencies = {
  ...pkg.devDependencies,
  'prisma': '^5.20.0',
};
pkg.scripts = {
  ...pkg.scripts,
  'prisma:generate': 'prisma generate',
  'prisma:migrate:dev': 'prisma migrate dev',
  'prisma:migrate:deploy': 'prisma migrate deploy',
};
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
" 2>/dev/null || fail "No se encontró Node para actualizar package.json — agregá las dependencias manualmente (ver README)"

ok "package.json actualizado"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ real-ecommerce-back funcional${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Módulos generados: catalog, inventory, customers, activity, cart, orders"
echo "Integración: OrganizationsClientService → real-back (GET /auth/organization-access)"
echo ""
echo "Próximos pasos:"
echo "  1. cp .env.example .env   (completar DATABASE_URL, Firebase, ORGANIZATIONS_SERVICE_URL)"
echo "  2. pnpm install"
echo "  3. pnpm prisma:migrate:dev --name init"
echo "  4. pnpm start:dev"
echo ""
echo "Pendiente (fuera de este scaffold, ver notas en el código):"
echo "  - Confirmar con real-back si CollaboratorPermissions ya tiene campos"
echo "    específicos de e-commerce, o si por ahora solo distinguimos OWNER/COLLABORATOR."
echo "  - Conectar pasarela-pagos cuando corresponda (Order.paymentIntentId ya existe)."
echo "  - StorefrontSettings (slug/dominio público) si se necesita resolución pública fuera del dashboard."