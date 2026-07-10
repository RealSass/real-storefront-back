#!/usr/bin/env bash
set -euo pipefail

# ─── Configuración ─────────────────────────────────────────────────────────
# Por defecto usa el directorio actual (ejecutar parado en la raíz del repo)
APP_DIR="${1:-.}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[i]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ -d "$APP_DIR" ] || err "No existe el directorio: $APP_DIR"
cd "$APP_DIR"

[ -f "package.json" ] || err "No se encontró package.json en $APP_DIR (¿estás parado en la raíz del repo?)"

# ─── 0. Guardias ───────────────────────────────────────────────────────────
if [ ! -f "prisma.config.ts" ]; then
  err "prisma.config.ts no encontrado. Este script asume que ya existe (fue el causante del error de build)."
fi

if [ ! -f "prisma/schema.prisma" ]; then
  err "prisma/schema.prisma no encontrado. Sin schema no tiene sentido instalar el cliente de Prisma."
fi

# ─── 1. Verificar qué falta antes de tocar nada ────────────────────────────
log "Chequeando dependencias actuales de Prisma en package.json..."

node -e "
  const pkg = require('./package.json');
  const deps = { ...pkg.dependencies };
  const devDeps = { ...pkg.devDependencies };
  const needDeps = ['@prisma/client', '@prisma/adapter-pg', 'pg', 'dotenv'];
  const needDevDeps = ['prisma'];
  const missing = { deps: [], dev: [] };
  for (const d of needDeps) if (!deps[d]) missing.deps.push(d);
  for (const d of needDevDeps) if (!devDeps[d]) missing.dev.push(d);
  console.log(JSON.stringify(missing));
" > /tmp/missing_deps.json

DEPS_JSON=$(cat /tmp/missing_deps.json)
log "Resultado: $DEPS_JSON"

MISSING_DEPS_LIST=$(node -e "console.log(JSON.parse(process.argv[1]).deps.join(' '))" "$DEPS_JSON")
MISSING_DEV_LIST=$(node -e "console.log(JSON.parse(process.argv[1]).dev.join(' '))" "$DEPS_JSON")

# ─── 2. Instalar dependencias faltantes ────────────────────────────────────
if [ -n "$MISSING_DEPS_LIST" ]; then
  log "Instalando dependencias de producción faltantes: $MISSING_DEPS_LIST"
  pnpm add \
    @prisma/client@^7.4.2 \
    @prisma/adapter-pg@^7.4.2 \
    pg@^8.19.0 \
    dotenv@^17.3.1
  ok "Dependencias de producción instaladas"
else
  ok "Dependencias de producción ya estaban completas"
fi

if [ -n "$MISSING_DEV_LIST" ]; then
  log "Instalando devDependencies faltantes: $MISSING_DEV_LIST"
  pnpm add -D prisma@^7.4.2
  ok "prisma (CLI) instalado como devDependency"
else
  ok "prisma (CLI) ya estaba en devDependencies"
fi

# ─── 3. .npmrc: permitir build scripts de prisma ───────────────────────────
if [ ! -f ".npmrc" ]; then
  log "Creando .npmrc..."
  cat > .npmrc << 'EOF'
shamefully-hoist=true
allow-build[]=@prisma/engines
allow-build[]=prisma
allow-build[]=protobufjs
allow-build[]=unrs-resolver
fund=false
update-notifier=false
EOF
  ok ".npmrc creado"
else
  if ! grep -q "allow-build\[\]=prisma$" .npmrc 2>/dev/null; then
    log "Agregando allow-build para prisma en .npmrc existente..."
    printf '\nallow-build[]=prisma\nallow-build[]=@prisma/engines\n' >> .npmrc
    ok ".npmrc actualizado"
  else
    ok ".npmrc ya tenía los permisos de build necesarios"
  fi
fi

# ─── 4. Validar el generator del schema ────────────────────────────────────
if ! grep -q 'engineType\s*=\s*"client"' prisma/schema.prisma; then
  echo -e "${YELLOW}[!] Advertencia:${NC} prisma/schema.prisma no tiene engineType = \"client\" en el generator."
  echo "    Si usás @prisma/adapter-pg (driver adapters), revisá el bloque generator manualmente:"
  echo '    generator client {'
  echo '      provider   = "prisma-client-js"'
  echo '      engineType = "client"'
  echo '    }'
fi

# ─── 5. Reinstalar y validar build local ───────────────────────────────────
log "Reinstalando dependencias (pnpm install)..."
pnpm install

log "Generando Prisma Client..."
pnpm exec prisma generate

log "Corriendo build de Nest para validar localmente antes de pushear..."
pnpm run build

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ real-ecommerce-back: dependencias de Prisma corregidas${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Próximo paso: commitear package.json + pnpm-lock.yaml + .npmrc y redeployar en Railway."