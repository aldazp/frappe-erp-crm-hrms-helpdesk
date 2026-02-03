#!/usr/bin/env bash
set -euo pipefail

### ========= CONFIG (ADJUST HERE) =========
TRAEFIK_DOMAIN="traefik.yourdomain.local"
LE_EMAIL="yourmail@yourdomain.local"
TRAEFIK_DASH_USER="admin"
TRAEFIK_DASH_PASS_PLAIN="StrongPassword"          # Automatice hashing

DB_PASSWORD="StrongPassword"                      # Password app user del stack mariadb-shared
DB_ROOT_PASSWORD="StrongPassword"                 # root mariadb
ADMIN_PASSWORD="StrongPassword"                   # Administrator ERPNext

SITE_FQDN="erp.yourdomain.local"

PROJECT_TRAEFIK="traefik"
PROJECT_MARIADB="mariadb"
PROJECT_ERP="erpnext-one"

# Base version of ERPNext container
ERP_IMAGE_BASE="frappe/erpnext:v15.95.2"
ERP_CUSTOM_IMAGE="yourdomain/erpnext:v15.95.2-hrms-crm-helpdesk"

# App branches
ERP_BRANCH="version-15"
HRMS_BRANCH="version-15"
CRM_BRANCH="main"
TELEPHONY_BRANCH="develop"
HELPDESK_BRANCH="main"

# Folders
REPO_DIR="$HOME/frappe_docker"
GITOPS_DIR="$HOME/gitops"

### ========= END CONFIG =========

log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando: $1"
}

ensure_repo() {
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    log "Clonando frappe_docker en $REPO_DIR"
    git clone https://github.com/frappe/frappe_docker "$REPO_DIR"
  else
    log "Repo ya existe: $REPO_DIR"
  fi
}

ensure_gitops() {
  mkdir -p "$GITOPS_DIR"
}

write_traefik_env() {
  log "Escribiendo $GITOPS_DIR/traefik.env"
  local hashed
  hashed="$(openssl passwd -apr1 "$TRAEFIK_DASH_PASS_PLAIN")"
  cat > "$GITOPS_DIR/traefik.env" <<EOF
TRAEFIK_DOMAIN=$TRAEFIK_DOMAIN
EMAIL=$LE_EMAIL
HASHED_PASSWORD='$hashed'
EOF
}

write_mariadb_env() {
  log "Escribiendo $GITOPS_DIR/mariadb.env"
  cat > "$GITOPS_DIR/mariadb.env" <<EOF
DB_PASSWORD=$DB_PASSWORD
EOF
}

write_erp_env() {
  log "Generando $GITOPS_DIR/$PROJECT_ERP.env desde example.env"
  cp -f "$REPO_DIR/example.env" "$GITOPS_DIR/$PROJECT_ERP.env"

  sed -i "s/DB_PASSWORD=123/DB_PASSWORD=$DB_PASSWORD/g" "$GITOPS_DIR/$PROJECT_ERP.env"
  sed -i "s/DB_HOST=/DB_HOST=mariadb-database/g" "$GITOPS_DIR/$PROJECT_ERP.env"
  sed -i "s/DB_PORT=/DB_PORT=3306/g" "$GITOPS_DIR/$PROJECT_ERP.env"

  sed -i "s/Host(\`erp.example.com\`)/Host(\`$SITE_FQDN\`)/g" "$GITOPS_DIR/$PROJECT_ERP.env" || true
  sed -i "s/erp.example.com/$SITE_FQDN/g" "$GITOPS_DIR/$PROJECT_ERP.env" || true

  grep -q '^ROUTER=' "$GITOPS_DIR/$PROJECT_ERP.env" || echo "ROUTER=$PROJECT_ERP" >> "$GITOPS_DIR/$PROJECT_ERP.env"
  grep -q '^BENCH_NETWORK=' "$GITOPS_DIR/$PROJECT_ERP.env" || echo "BENCH_NETWORK=$PROJECT_ERP" >> "$GITOPS_DIR/$PROJECT_ERP.env"
}

write_apps_json() {
  log "Escribiendo $GITOPS_DIR/apps.json"
  cat > "$GITOPS_DIR/apps.json" <<EOF
[
  { "url": "https://github.com/frappe/erpnext",    "branch": "$ERP_BRANCH" },
  { "url": "https://github.com/frappe/hrms",      "branch": "$HRMS_BRANCH" },
  { "url": "https://github.com/frappe/crm",       "branch": "$CRM_BRANCH" },
  { "url": "https://github.com/frappe/telephony", "branch": "$TELEPHONY_BRANCH" },
  { "url": "https://github.com/frappe/helpdesk",  "branch": "$HELPDESK_BRANCH" }
]
EOF
}

build_custom_image() {
  log "Construyendo imagen custom: $ERP_CUSTOM_IMAGE"
  local apps_b64
  apps_b64="$(base64 -w 0 "$GITOPS_DIR/apps.json")"

  cd "$REPO_DIR"
  docker build \
    --build-arg=APPS_JSON_BASE64="$apps_b64" \
    -t "$ERP_CUSTOM_IMAGE" \
    -f images/custom/Containerfile .
}

write_compose_override_custom_image() {
  log "Escribiendo $GITOPS_DIR/compose.custom-image.yaml"
  cat > "$GITOPS_DIR/compose.custom-image.yaml" <<EOF
services:
  backend:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  configurator:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  frontend:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  queue-long:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  queue-short:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  scheduler:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
  websocket:
    image: $ERP_CUSTOM_IMAGE
    pull_policy: if_not_present
EOF
}

deploy_traefik() {
  log "Levantando Traefik ($PROJECT_TRAEFIK)"
  cd "$REPO_DIR"
  docker compose --project-name "$PROJECT_TRAEFIK" \
    --env-file "$GITOPS_DIR/traefik.env" \
    -f overrides/compose.traefik.yaml \
    -f overrides/compose.traefik-ssl.yaml up -d
}

deploy_mariadb() {
  log "Levantando MariaDB ($PROJECT_MARIADB)"
  cd "$REPO_DIR"
  docker compose --project-name "$PROJECT_MARIADB" \
    --env-file "$GITOPS_DIR/mariadb.env" \
    -f overrides/compose.mariadb-shared.yaml up -d
}

render_erp_yaml() {
  log "Renderizando YAML final $GITOPS_DIR/$PROJECT_ERP.yaml"
  cd "$REPO_DIR"
  docker compose --project-name "$PROJECT_ERP" \
    --env-file "$GITOPS_DIR/$PROJECT_ERP.env" \
    -f compose.yaml \
    -f overrides/compose.redis.yaml \
    -f overrides/compose.multi-bench.yaml \
    -f overrides/compose.multi-bench-ssl.yaml \
    -f "$GITOPS_DIR/compose.custom-image.yaml" \
    config > "$GITOPS_DIR/$PROJECT_ERP.yaml"
}

deploy_erp() {
  log "Levantando ERPNext ($PROJECT_ERP)"
  docker compose --project-name "$PROJECT_ERP" -f "$GITOPS_DIR/$PROJECT_ERP.yaml" up -d
}

site_exists() {
  docker compose --project-name "$PROJECT_ERP" -f "$GITOPS_DIR/$PROJECT_ERP.yaml" exec -T backend \
    bash -lc "test -d sites/$SITE_FQDN" >/dev/null 2>&1
}

create_site_if_needed() {
  if site_exists; then
    log "Site ya existe: $SITE_FQDN (no se recrea)"
    return 0
  fi

  log "Creando site $SITE_FQDN e instalando apps (erpnext, hrms, crm, telephony, helpdesk)"
  docker compose --project-name "$PROJECT_ERP" -f "$GITOPS_DIR/$PROJECT_ERP.yaml" exec -T backend \
    bench new-site \
      --mariadb-user-host-login-scope=% \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --install-app erpnext \
      --install-app hrms \
      --install-app crm \
      --install-app telephony \
      --install-app helpdesk \
      "$SITE_FQDN"
}

post_checks() {
  log "Verificación: contenedores principales"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | egrep "traefik|mariadb|$PROJECT_ERP" || true

  log "Verificación: apps instaladas"
  docker compose --project-name "$PROJECT_ERP" -f "$GITOPS_DIR/$PROJECT_ERP.yaml" exec -T backend \
    bench --site "$SITE_FQDN" list-apps || true

  log "Listo. URL esperada: https://$SITE_FQDN"
}

main() {
  need_cmd git
  need_cmd docker
  need_cmd openssl
  need_cmd base64

  ensure_gitops
  ensure_repo

  write_traefik_env
  write_mariadb_env
  write_erp_env
  write_apps_json

  deploy_traefik
  deploy_mariadb

  build_custom_image
  write_compose_override_custom_image

  render_erp_yaml
  deploy_erp

  create_site_if_needed
  post_checks
}

main "$@"