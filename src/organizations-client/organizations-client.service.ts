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
