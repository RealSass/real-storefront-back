#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-.}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[i]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd "$APP_DIR"
FILE="src/redis/redis.service.ts"
[ -f "$FILE" ] || err "No se encontró $FILE"

log "Reescribiendo $FILE con guard de REDIS_ENABLED..."

cat > "$FILE" << 'EOF'
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
EOF
ok "$FILE reescrito con guard de REDIS_ENABLED"

# ─── Documentar la var si hay .env.example ──────────────────────────────────
if [ -f ".env.example" ]; then
  if ! grep -q "^REDIS_ENABLED=" .env.example; then
    cat >> .env.example << 'EOF'

# ─── Redis (cache de org-access) ───────────────────────────────────────────
# REDIS_ENABLED=true  → cache activo (requiere REDIS_URL configurada).
# REDIS_ENABLED=false (o ausente) → no-op, sin intentos de conexión.
REDIS_ENABLED=false
EOF
    ok ".env.example actualizado"
  fi
fi

log "Recompilando para validar..."
rm -f *.tsbuildinfo
pnpm run build

if [ -f "dist/main.js" ]; then
  ok "Build OK — dist/main.js generado"
else
  err "El build no generó dist/main.js — revisar output de arriba"
fi

echo ""
echo -e "${GREEN}✅ RedisService ahora respeta REDIS_ENABLED${NC}"
echo ""
echo "Commiteá y pusheá, y en Railway agregá la variable:"
echo "  REDIS_ENABLED=false   (mientras no tengas Redis provisionado para este servicio)"