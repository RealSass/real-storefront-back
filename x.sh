#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-.}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[i]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd "$APP_DIR"
[ -f "package.json" ] || err "No se encontró package.json"

log "Corrigiendo start/start:prod → node dist/main.js..."
node -e "
  const fs = require('fs');
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  pkg.scripts.start = 'node dist/main.js';
  pkg.scripts['start:prod'] = 'node dist/main.js';
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
ok "package.json corregido"

log "Recompilando desde cero para confirmar la ruta real..."
rm -rf dist
pnpm run build

if [ -f "dist/main.js" ]; then
  ok "dist/main.js confirmado"
else
  echo -e "${RED}Estructura actual de dist/:${NC}"
  find dist -maxdepth 2
  err "dist/main.js sigue sin aparecer donde se espera"
fi

log "Probando arranque local (3s, luego se corta)..."
node dist/main.js &
PID=$!
sleep 3
if kill -0 "$PID" 2>/dev/null; then
  ok "Levantó correctamente"
  kill "$PID" 2>/dev/null || true
else
  echo -e "${YELLOW}[!]${NC} El proceso terminó antes de los 3s — revisá el log de arriba (puede ser falta de DATABASE_URL local, no necesariamente un error del fix)"
fi

echo ""
echo -e "${GREEN}✅ Listo — commiteá package.json y redeployá en Railway${NC}"