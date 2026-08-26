#!/usr/bin/env bash
set -euo pipefail

### Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

### Configurações
APACHE_PORT=8080
APACHE_IP=127.0.0.1
WEBROOT="/var/www/html"
NGINX_SITE="apache-proxy"
SERVER_NAME="_"

INSTALL_MARIADB=0
MARIADB_ROOT_PASS="${MARIADB_ROOT_PASS:-}"   # vazio = gera automaticamente
MARIADB_BIND="0.0.0.0"                       # "::" para IPv4+IPv6
MARIADB_CNF="/etc/mysql/mariadb.conf.d/99-remote.cnf"

### Funções auxiliares
need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}[ERRO]${NC} Execute como root: ${YELLOW}sudo $0${NC}"
    exit 1
  fi
}
is_cmd() { command -v "$1" &>/dev/null; }
backup_file() { local f="$1"; [[ -f "$f" && ! -f "${f}.bak" ]] && cp -a "$f" "${f}.bak"; }
msg()     { echo -e "\n${BLUE}>>>${NC} $1\n"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; }
err()     { echo -e "${RED}[ERRO]${NC} $1"; }

show_help() {
  echo -e "${CYAN}apache-nginx-auto${NC} — Instalação automática de Nginx + Apache + PHP (+ MariaDB opcional)"
  echo ""
  echo -e "Uso: ${YELLOW}sudo ./autoinstall.sh${NC} [opções]"
  echo ""
  echo "Opções:"
  echo "  --help              Mostra esta mensagem"
  echo "  --status            Verifica o status dos serviços"
  echo "  --uninstall         Remove Nginx, Apache, PHP e MariaDB instalados pelo script"
  echo "  --mariadb           Instala MariaDB junto (root com senha, acesso de qualquer IP)"
  echo "  --db-pass SENHA     Senha do root do MariaDB (ou env MARIADB_ROOT_PASS; padrão: gerada)"
  echo "  (sem opção)         Executa a instalação completa sem MariaDB"
  echo ""
  echo "Configurações padrão:"
  echo "  Nginx:    porta 80 (proxy reverso)"
  echo "  Apache:   porta ${APACHE_PORT} (backend PHP)"
  echo "  MariaDB:  porta 3306, bind ${MARIADB_BIND}"
  echo "  Webroot:  ${WEBROOT}"
  exit 0
}

show_status() {
  need_root
  echo -e "${CYAN}=== Status dos Serviços ===${NC}\n"

  svcs=(nginx apache2)
  dpkg -s mariadb-server &>/dev/null && svcs+=(mariadb)
  for svc in "${svcs[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      success "$svc está rodando"
    else
      err "$svc não está rodando"
    fi
  done

  echo ""
  if is_cmd php; then
    success "PHP $(php -r 'echo PHP_VERSION;') instalado"
  else
    err "PHP não encontrado"
  fi

  echo ""
  echo -e "${CYAN}Portas em uso:${NC}"
  ss -tlnp 2>/dev/null | grep -E ':80\s|:8080\s|:3306\s' || warn "Nenhuma porta 80/8080/3306 encontrada"

  echo ""
  if nginx -t 2>/dev/null; then
    success "Configuração do Nginx válida"
  else
    err "Configuração do Nginx com erros"
  fi
  exit 0
}

do_uninstall() {
  need_root
  echo -e "${RED}=== Desinstalação ===${NC}\n"
  warn "Isso vai remover Nginx, Apache, PHP e MariaDB do sistema."
  read -rp "Tem certeza? (s/N): " confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && { echo "Cancelado."; exit 0; }

  msg "Parando serviços..."
  systemctl stop nginx apache2 mariadb 2>/dev/null || true
  systemctl disable nginx apache2 mariadb 2>/dev/null || true

  msg "Removendo pacotes..."
  apt-get purge -y nginx nginx-common apache2 apache2-utils \
    php libapache2-mod-php php-cli php-common php-curl php-xml php-mbstring php-mysql php-zip \
    mariadb-server mariadb-client 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true

  msg "Removendo configurações do script..."
  rm -f "/etc/nginx/sites-available/${NGINX_SITE}" "/etc/nginx/sites-enabled/${NGINX_SITE}"
  rm -f "$MARIADB_CNF" /root/.my.cnf

  for f in /etc/apache2/ports.conf /etc/apache2/sites-available/000-default.conf; do
    [[ -f "${f}.bak" ]] && mv "${f}.bak" "$f" && success "Backup restaurado: $f"
  done

  if [[ -d /var/lib/mysql ]]; then
    read -rp "Remover dados do MariaDB (/var/lib/mysql)? (s/N): " rmdata
    if [[ "$rmdata" == "s" || "$rmdata" == "S" ]]; then
      rm -rf /var/lib/mysql /etc/mysql
      success "Dados do MariaDB removidos"
    fi
  fi

  success "Desinstalação concluída."
  exit 0
}

### Parse de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)      show_help ;;
    --status|-s)    show_status ;;
    --uninstall|-u) do_uninstall ;;
    --mariadb|-m)   INSTALL_MARIADB=1 ;;
    --db-pass)      [[ -n "${2:-}" ]] || { err "--db-pass requer uma senha"; exit 1; }
                    MARIADB_ROOT_PASS="$2"; INSTALL_MARIADB=1; shift ;;
    --db-pass=*)    MARIADB_ROOT_PASS="${1#*=}"; INSTALL_MARIADB=1 ;;
    *)              err "Opção desconhecida: $1"; show_help ;;
  esac
  shift
done

### Início
need_root

if ! is_cmd apt-get; then
  err "Este script foi feito para Ubuntu/Debian (apt)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

msg "Atualizando pacotes…"
apt-get update -y
apt-get upgrade -y
success "Pacotes atualizados"

msg "Instalando Nginx, Apache e PHP…"
apt-get install -y nginx apache2 \
  php libapache2-mod-php php-cli php-common php-curl php-xml php-mbstring php-mysql php-zip
success "Pacotes instalados"

msg "Ajustando Apache para escutar em ${APACHE_IP}:${APACHE_PORT}…"
backup_file /etc/apache2/ports.conf
if grep -qE '^\s*Listen\s' /etc/apache2/ports.conf; then
  sed -ri "s#^\s*Listen\s+.*#Listen ${APACHE_IP}:${APACHE_PORT}#g" /etc/apache2/ports.conf
else
  echo "Listen ${APACHE_IP}:${APACHE_PORT}" >> /etc/apache2/ports.conf
fi

backup_file /etc/apache2/sites-available/000-default.conf
if grep -q "<VirtualHost" /etc/apache2/sites-available/000-default.conf; then
  sed -ri "s#<VirtualHost\s+[^>]*>#<VirtualHost *:${APACHE_PORT}>#g" /etc/apache2/sites-available/000-default.conf
else
  cat > /etc/apache2/sites-available/000-default.conf <<CONF
<VirtualHost *:${APACHE_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${WEBROOT}
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CONF
fi

a2dismod mpm_event >/dev/null 2>&1 || true
a2enmod mpm_prefork >/dev/null 2>&1 || true
a2enmod php* >/dev/null 2>&1 || true
a2enmod rewrite headers >/dev/null 2>&1 || true
a2enmod remoteip >/dev/null 2>&1 || true

if [[ ! -f /etc/apache2/conf-available/remoteip.conf ]]; then
  cat >/etc/apache2/conf-available/remoteip.conf <<'CONF'
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 127.0.0.1
LogFormat "%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
CustomLog ${APACHE_LOG_DIR}/access.log combined
CONF
fi
a2enconf remoteip >/dev/null 2>&1 || true

systemctl enable apache2
systemctl restart apache2
success "Apache configurado na porta ${APACHE_PORT}"

msg "Criando página PHP de teste em ${WEBROOT}/index.php…"
install -d -m 0755 "$WEBROOT"
if [[ ! -f "${WEBROOT}/index.php" ]]; then
  cat > "${WEBROOT}/index.php" <<'PHP'
<?php
phpinfo();
PHP
fi
chown -R www-data:www-data "$WEBROOT"
success "Página de teste criada"

msg "Configurando Nginx com estáticos diretos e proxy para Apache…"
cat > "/etc/nginx/sites-available/${NGINX_SITE}" <<NGX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${SERVER_NAME};

    root ${WEBROOT};
    index index.php index.html index.htm;

    client_max_body_size 64m;

    location / {
        try_files \$uri \$uri/ @apache;
    }

    location ~ \.php$ {
        proxy_pass http://${APACHE_IP}:${APACHE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host  \$host;
        proxy_set_header X-Forwarded-Port  \$server_port;
        proxy_redirect off;
        proxy_buffering on;
        proxy_read_timeout 300;
    }

    location @apache {
        proxy_pass http://${APACHE_IP}:${APACHE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host  \$host;
        proxy_set_header X-Forwarded-Port  \$server_port;
        proxy_redirect off;
        proxy_buffering on;
        proxy_read_timeout 300;
    }

    location ~* \.(?:jpg|jpeg|png|gif|webp|ico|svg|css|js|woff2?|ttf|otf)$ {
        try_files \$uri @apache;
        expires 7d;
        add_header Cache-Control "public, max-age=604800, must-revalidate";
        etag on;
        access_log off;
    }

    location ~* /(?:\.git|\.hg|\.svn|backups?|dump|logs?|temp|cache)/ { deny all; }
    location ~* \.(?:env|ini|log|sql|bak|swp)$ { deny all; }
    location = /composer.json  { deny all; }
    location = /composer.lock  { deny all; }
}
NGX

ln -sf "/etc/nginx/sites-available/${NGINX_SITE}" "/etc/nginx/sites-enabled/${NGINX_SITE}"
[[ -e /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

msg "Testando configuração do Nginx…"
nginx -t
success "Configuração do Nginx válida"

systemctl enable nginx
systemctl restart nginx
success "Nginx rodando"

### MariaDB (opcional)
if [[ "$INSTALL_MARIADB" -eq 1 ]]; then
  msg "Instalando MariaDB…"
  apt-get install -y mariadb-server mariadb-client
  success "MariaDB instalado"

  if [[ -z "$MARIADB_ROOT_PASS" ]]; then
    MARIADB_ROOT_PASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
    MARIADB_ROOT_PASS="${MARIADB_ROOT_PASS:0:20}"
    warn "Senha do root gerada automaticamente (veja o resumo no final)"
  fi

  msg "Liberando acesso remoto (bind ${MARIADB_BIND})…"
  cat > "$MARIADB_CNF" <<CONF
# Gerado por autoinstall.sh
[mysqld]
bind-address      = ${MARIADB_BIND}
skip-name-resolve = 1
CONF

  systemctl enable mariadb
  systemctl restart mariadb
  success "MariaDB escutando em ${MARIADB_BIND}:3306"

  msg "Configurando root (local + remoto)…"
  MYSQL_BIN="$(command -v mariadb || command -v mysql)"
  mysql_root() { "$MYSQL_BIN" --protocol=socket -uroot -e "$1"; }
  pass_sql="${MARIADB_ROOT_PASS//\\/\\\\}"
  pass_sql="${pass_sql//\'/\'\'}"

  # >= 10.4: senha + unix_socket (mantém 'sudo mysql' e logrotate); < 10.4: só senha
  mysql_root "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${pass_sql}') OR unix_socket;" 2>/dev/null \
    || mysql_root "ALTER USER 'root'@'localhost' IDENTIFIED BY '${pass_sql}';"

  mysql_root "CREATE OR REPLACE USER 'root'@'%' IDENTIFIED BY '${pass_sql}';
              GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
              FLUSH PRIVILEGES;"

  cat > /root/.my.cnf <<CONF
[client]
user=root
password="${MARIADB_ROOT_PASS}"
CONF
  chmod 600 /root/.my.cnf
  success "root@localhost e root@% configurados com senha"
fi

if is_cmd ufw; then
  msg "Ajustando UFW (firewall)…"
  ufw allow 'Nginx Full' || true
  if [[ "$INSTALL_MARIADB" -eq 1 ]]; then ufw allow 3306/tcp || true; fi
  ufw delete allow 'Apache Full' >/dev/null 2>&1 || true
  ufw delete allow 8080/tcp    >/dev/null 2>&1 || true
  success "Firewall configurado"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalação concluída com sucesso!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Nginx (porta 80) → Apache (porta ${APACHE_PORT})"
echo -e "  PHP executando no Apache via mod_php"
echo -e "  Webroot: ${WEBROOT}"
echo ""
if [[ "$INSTALL_MARIADB" -eq 1 ]]; then
  echo -e "  MariaDB: ${MARIADB_BIND}:3306 (root liberado de qualquer IP)"
  echo -e "    Senha root: ${YELLOW}${MARIADB_ROOT_PASS}${NC}  (salva em /root/.my.cnf)"
  echo -e "    Teste: ${CYAN}mysql -h SEU_IP -uroot -p${NC}"
  echo ""
fi
echo -e "  Teste: ${CYAN}curl -I http://127.0.0.1/${NC}"
echo -e "  Ou abra no navegador: ${CYAN}http://SEU_IP/${NC}"
echo ""
echo -e "  Comandos úteis:"
echo -e "    ${YELLOW}sudo ./autoinstall.sh --status${NC}      Verifica serviços"
echo -e "    ${YELLOW}sudo ./autoinstall.sh --uninstall${NC}   Remove tudo"
echo ""
