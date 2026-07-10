#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-.}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[i]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd "$APP_DIR"
[ -f "tsconfig.json" ] || err "No se encontró tsconfig.json"
[ -f "package.json" ]  || err "No se encontró package.json"

log "Fijando rootDir en tsconfig.json y excluyendo prisma.config.ts del build..."

node -e "
  const fs = require('fs');

  // ─── tsconfig.json ────────────────────────────────────────────────────
  const tsconfigPath = 'tsconfig.json';
  const tsconfig = JSON.parse(fs.readFileSync(tsconfigPath, 'utf8'));
  tsconfig.compilerOptions = tsconfig.compilerOptions || {};
  tsconfig.compilerOptions.rootDir = 'src';
  fs.writeFileSync(tsconfigPath, JSON.stringify(tsconfig, null, 2) + '\n');
  console.log('tsconfig.json → rootDir: \"src\"');

  // ─── tsconfig.build.json (si existe) ────────────────────────────────────
  const buildPath = 'tsconfig.build.json';
  if (fs.existsSync(buildPath)) {
    const build = JSON.parse(fs.readFileSync(buildPath, 'utf8'));
    build.exclude = Array.from(new Set([...(build.exclude || []), 'prisma.config.ts', 'prisma/**']));
    fs.writeFileSync(buildPath, JSON.stringify(build, null, 2) + '\n');
    console.log('tsconfig.build.json → excluye prisma.config.ts y prisma/');
  } else {
    console.log('No hay tsconfig.build.json, se crea uno mínimo.');
    fs.writeFileSync(buildPath, JSON.stringify({
      extends: './tsconfig.json',
      exclude: ['node_modules', 'test', 'dist', '**/*spec.ts', 'prisma.config.ts', 'prisma/**'],
    }, null, 2) + '\n');
  }
"

ok "tsconfig actualizado"

# ─── Revertir package.json a dist/main.js (ruta estándar, ya corregida por rootDir) ─
log "Confirmando que package.json apunte a dist/main.js (ruta estándar)..."
node -e "
  const fs = require('fs');
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  pkg.scripts.start = 'node dist/main';
  pkg.scripts['start:prod'] = 'node dist/main';
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
ok "package.json OK (dist/main.js)"

# ─── Limpiar dist viejo y recompilar desde cero ────────────────────────────
log "Limpiando dist/ y recompilando..."
rm -rf dist
pnpm run build

if [ -f "dist/main.js" ]; then
  ok "dist/main.js generado correctamente en la raíz de dist/"
else
  echo ""
  echo -e "${RED}[✗] dist/main.js sigue sin aparecer. Estructura actual de dist/:${NC}"
  find dist -maxdepth 2 -type f
  err "Revisar manualmente — puede haber otro archivo .ts fuera de src/ ampliando el rootDir."
fi

log "Probando arranque con node dist/main.js (Ctrl+C para cortar tras confirmar que levanta)..."
echo -e "${YELLOW}Corriendo: node dist/main.js${NC}"
node dist/main.js &
NODE_PID=$!
sleep 3
if kill -0 "$NODE_PID" 2>/dev/null; then
  ok "El proceso levantó y sigue corriendo — matándolo (era solo para test)"
  kill "$NODE_PID" 2>/dev/null || true
else
  err "El proceso murió enseguida — revisá el log de arriba (probablemente falta alguna env var como DATABASE_URL)"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ rootDir corregido — dist/main.js en la ruta esperada${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo "Próximo paso: commitear tsconfig.json, tsconfig.build.json y package.json, y redeployar."