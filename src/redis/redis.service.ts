import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';

// REDIS_ENABLED=true  → se conecta normalmente (requiere REDIS_URL válida).
// REDIS_ENABLED=false (o ausente) → no-op total: nunca intenta conectar,
// get() siempre devuelve null (cache-miss), set()/del() no hacen nada.
// Útil en fase de prueba cuando todavía no hay Redis provisionado para este servicio.
const REDIS_ENABLED = process.env['REDIS_ENABLED'] === 'true';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private client: Redis | null = null;

  onModuleInit(): void {
    if (!REDIS_ENABLED) {
      this.logger.warn(
        'Redis deshabilitado (REDIS_ENABLED != true) — cache en modo no-op',
      );
      return;
    }

    this.client = new Redis(process.env['REDIS_URL'] ?? 'redis://localhost:6379', {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
      retryStrategy: (retries) => (retries > 10 ? null : Math.min(retries * 200, 10_000)),
    });
    this.client.on('error', (err) => this.logger.error('Redis error', err));
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client) await this.client.quit();
  }

  async get(key: string): Promise<string | null> {
    if (!REDIS_ENABLED || !this.client) return null;
    return this.client.get(key);
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    if (!REDIS_ENABLED || !this.client) return;
    await this.client.set(key, value, 'EX', ttlSeconds);
  }

  async del(key: string): Promise<void> {
    if (!REDIS_ENABLED || !this.client) return;
    await this.client.del(key);
  }
}
