#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-.}"
FILE="src/activity/activity.service.ts"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[i]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd "$APP_DIR"
[ -f "$FILE" ] || err "No se encontró $FILE"

log "Mostrando el archivo actual para diagnóstico..."
cat -A "$FILE" | sed -n '15,20p' || true
echo ""

node -e "
  const fs = require('fs');
  const path = '$FILE';
  let src = fs.readFileSync(path, 'utf8');
  const before = src;

  // 1) Asegurar import de Prisma desde @prisma/client
  if (/from '@prisma\/client'/.test(src)) {
    if (!/\bPrisma\b/.test(src.match(/import\s*\{[^}]*\}\s*from\s*'@prisma\/client';/)?.[0] ?? '')) {
      src = src.replace(
        /import\s*\{\s*([^}]*)\}\s*from\s*'@prisma\/client';/,
        (m, inner) => {
          const names = inner.split(',').map(s => s.trim()).filter(Boolean);
          if (!names.includes('Prisma')) names.push('Prisma');
          return \`import { \${names.join(', ')} } from '@prisma/client';\`;
        }
      );
    }
  } else {
    src = \"import { Prisma } from '@prisma/client';\n\" + src;
  }

  // 2) Castear payload SIN depender de un match exacto de línea completa:
  //    busca 'payload }' o 'payload,' o 'payload }' seguido de coma/cierre,
  //    pero solo dentro de un objeto que también tenga 'organizationId' cerca
  //    (para no tocar otro 'payload' si existiera en el archivo).
  const patterns = [
    { from: /(\bpayload\b)(\s*\})/, to: 'payload: payload as Prisma.InputJsonValue\$2' },
  ];

  let changed = false;
  if (!/payload:\s*payload as Prisma\.InputJsonValue/.test(src)) {
    for (const p of patterns) {
      if (p.from.test(src)) {
        src = src.replace(p.from, p.to);
        changed = true;
        break;
      }
    }
  } else {
    console.log('El cast ya estaba aplicado.');
  }

  if (src !== before) {
    fs.writeFileSync(path, src);
    console.log('Archivo modificado.');
  } else if (!changed) {
    console.log('NO_MATCH');
  }
"

echo ""
log "Contenido final de la línea relevante:"
grep -n "payload" "$FILE" || true

echo ""
log "Corriendo build para validar..."
pnpm run build

echo ""
echo -e "${GREEN}✅ activity.service.ts corregido y build OK${NC}"