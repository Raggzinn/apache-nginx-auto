# Apache + Nginx Auto

Script de instalação automática que configura Nginx como proxy reverso na frente do Apache com PHP em servidores Ubuntu/Debian.

> **Um comando** e o servidor está pronto para produção

---

## O que faz

```
Cliente → Nginx (porta 80) → Apache (porta 8080) → PHP
              ↓
        Arquivos estáticos
      (servidos direto pelo Nginx)
```

- Instala e configura **Nginx**, **Apache** e **PHP** automaticamente
- Nginx serve arquivos estáticos (CSS, JS, imagens) direto, sem passar pelo Apache
- Apache processa apenas requisições PHP via `mod_php`
- Configura **RemoteIP** para logs corretos atrás do proxy
- Cria backups das configs originais antes de alterar
- Bloqueia acesso a arquivos sensíveis (`.env`, `.git`, `.sql`, etc.)
- Cache de 7 dias para assets estáticos
- Configura UFW (firewall) se disponível

---

## Instalação rápida

```bash
curl -fsSL https://raw.githubusercontent.com/Raggzinn/apache-nginx-auto/main/autoinstall.sh | sudo bash
```

Ou clone e execute:

```bash
git clone https://github.com/Raggzinn/apache-nginx-auto.git
cd apache-nginx-auto
sudo bash autoinstall.sh
```

---

## Comandos

| Comando | Descrição |
|---------|-----------|
| `sudo ./autoinstall.sh` | Instalação completa |
| `sudo ./autoinstall.sh --status` | Verifica status dos serviços |
| `sudo ./autoinstall.sh --uninstall` | Remove tudo que foi instalado |
| `sudo ./autoinstall.sh --help` | Mostra ajuda |

---

## Configuração padrão

| Item | Valor |
|------|-------|
| Nginx | Porta 80 (proxy reverso) |
| Apache | Porta 8080 (backend, apenas localhost) |
| PHP | mod_php no Apache (prefork) |
| Webroot | `/var/www/html` |
| Firewall | Libera Nginx, bloqueia acesso direto ao Apache |

Para alterar, edite as variáveis no topo do `autoinstall.sh`.

---

## Requisitos

- Ubuntu ou Debian (usa `apt`)
- Acesso root (`sudo`)

---

## Contato

- [GitHub](https://github.com/Raggzinn/)
- [LinkedIn](https://www.linkedin.com/in/joaogoliveirac/)
- [Instagram](https://www.instagram.com/carrneiroo.j/)
