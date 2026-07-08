#!/usr/bin/env bash
#
# upload-release.sh
# Sube los archivos de release/<version>/ como GitHub Release assets.
#
# Uso:
#   ./upload-release.sh <version>              # Crea release y sube assets
#   ./upload-release.sh <version> --draft      # Crea como borrador
#   ./upload-release.sh <version> --upload-only # Solo sube assets a un release ya existente
#
# Ejemplo:
#   ./upload-release.sh 0.1.1
#   ./upload-release.sh 0.1.1 --draft
#   ./upload-release.sh 0.1.1 --upload-only
#
# Requisitos:
#   - gh CLI instalada y autenticada (gh auth login)
#   - Los archivos deben estar en release/<version>/

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Validaciones ─────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  error "Uso: $0 <version> [--draft | --upload-only]"
  echo ""
  echo "Ejemplos:"
  echo "  $0 0.1.1              # Crea release v0.1.1 y sube los archivos"
  echo "  $0 0.1.1 --draft      # Crea como borrador (no publicado)"
  echo "  $0 0.1.1 --upload-only # Solo sube archivos a un release ya existente"
  exit 1
fi

VERSION="$1"
shift

DRAFT=false
UPLOAD_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --draft)       DRAFT=true ;;
    --upload-only) UPLOAD_ONLY=true ;;
    *)
      error "Opción desconocida: $arg"
      exit 1
      ;;
  esac
done

# ─── Verificar gh CLI ─────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  error "gh CLI no está instalada."
  echo "  Instálala con: brew install gh"
  echo "  Luego autentícate: gh auth login"
  exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
  error "gh CLI no está autenticada."
  echo "  Ejecuta: gh auth login"
  exit 1
fi

ok "gh CLI detectada y autenticada."

# ─── Detectar repo ────────────────────────────────────────────────────────────
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
if [[ -z "$REPO" ]]; then
  error "No se pudo detectar el repositorio. Asegúrate de estar dentro de un repo de GitHub."
  exit 1
fi
info "Repositorio: ${REPO}"

# ─── Directorio de release ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${SCRIPT_DIR}/release/${VERSION}"

if [[ ! -d "$RELEASE_DIR" ]]; then
  error "No existe el directorio: ${RELEASE_DIR}"
  echo "  Crea la carpeta release/${VERSION}/ y coloca allí los archivos a subir."
  exit 1
fi

# ─── Buscar archivos a subir ─────────────────────────────────────────────────
mapfile -t FILES < <(find "$RELEASE_DIR" -maxdepth 1 -type f ! -name '.*' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  error "No hay archivos en release/${VERSION}/"
  exit 1
fi

info "Archivos a subir (${#FILES[@]}):"
for f in "${FILES[@]}"; do
  SIZE=$(du -h "$f" | cut -f1)
  echo "  - $(basename "$f")  (${SIZE})"
done

TAG="v${VERSION}"

# ─── Crear release o solo subir assets ────────────────────────────────────────
if [[ "$UPLOAD_ONLY" == true ]]; then
  info "Subiendo archivos al release existente '${TAG}'..."
  for f in "${FILES[@]}"; do
    info "  Subiendo $(basename "$f")..."
    if gh release upload "$TAG" "$f" --clobber; then
      ok "  $(basename "$f") subido correctamente."
    else
      error "  Error al subir $(basename "$f")"
      exit 1
    fi
  done
else
  DRAFT_FLAG=""
  if [[ "$DRAFT" == true ]]; then
    DRAFT_FLAG="--draft"
    info "Creando release '${TAG}' como BORRADOR..."
  else
    info "Creando release '${TAG}'..."
  fi

  # Construir argumentos
  # shellcheck disable=SC2086
  if gh release create "$TAG" ${DRAFT_FLAG} \
    --title "BeatPlay Bridge ${TAG}" \
    --notes "## BeatPlay Bridge ${TAG}

### Archivos incluidos
$(for f in "${FILES[@]}"; do echo "- $(basename "$f")"; done)

---
_Subido automáticamente con upload-release.sh_" \
    "${FILES[@]}"; then
    ok "Release '${TAG}' creado y archivos subidos correctamente."
  else
    error "Error al crear el release."
    exit 1
  fi
fi

echo ""
ok "¡Listo! Release disponible en:"
echo -e "  ${BLUE}https://github.com/${REPO}/releases/tag/${TAG}${NC}"
