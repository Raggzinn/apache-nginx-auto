#!/usr/bin/env bash
set -euo pipefail

### Configurações
APACHE_PORT=8080
APACHE_IP=127.0.0.1
WEBROOT="/var/www/html"
NGINX_SITE="apache-proxy"
SERVER_NAME="_"

### Funções auxiliares
need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Execute como root: sudo $0"
    exit 1
  fi
}
is_cmd() { command -v "$1" &>/dev/null; }
backup_file() { local f="$1"; [[ -f "$f" && ! -f "${f}.bak" ]] && cp -a "$f" "${f}.bak"; }
msg() { echo -e "\n>>>> $1\n"; }

### Início
need_root

if ! is_cmd apt-get; then
  echo "Este script foi feito para Ubuntu/Debian (apt)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

msg "Atualizando pacotes…"
apt-get update -y
apt-get upgrade -y

msg "Instalando Nginx, Apache e PHP…"
apt-get install -y nginx apache2 \
  php libapache2-mod-php php-cli php-common php-curl php-xml php-mbstring php-mysql php-zip

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

msg "Criando página PHP de teste em ${WEBROOT}/index.php…"
install -d -m 0755 "$WEBROOT"
if [[ ! -f "${WEBROOT}/index.php" ]]; then
  cat > "${WEBROOT}/index.php" <<'PHP'
<?php
phpinfo();
PHP
fi
chown -R www-data:www-data "$WEBROOT"

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

systemctl enable nginx
systemctl restart nginx

if is_cmd ufw; then
  msg "Ajustando UFW (firewall)…"
  ufw allow 'Nginx Full' || true
  ufw delete allow 'Apache Full' >/dev/null 2>&1 || true
  ufw delete allow 8080/tcp    >/dev/null 2>&1 || true
fi

msg "Pronto! Nginx (80) → Apache ${APACHE_IP}:${APACHE_PORT}. PHP executa no Apache."
echo "Teste no navegador: http://SEU_IP/  (deve abrir o phpinfo())"
echo "Se estiver na própria máquina: curl -I http://127.0.0.1/"
