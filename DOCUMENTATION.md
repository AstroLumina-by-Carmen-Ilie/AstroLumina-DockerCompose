# Documentație Tehnică AstroLumina - Docker & Infrastructure

## Cuprins

1. [ docker-compose.yml ](#1-docker-composeyml)
2. [ traefik/traefik.yml ](#2-traefiktraefikyml)
3. [ traefik/dynamic.yml ](#3-traefikdynamicyml)
4. [ AstroLumina-Frontend/Dockerfile ](#4-astroalumina-frontenddockerfile)
5. [ AstroLumina-Frontend/nginx.conf ](#5-astroalumina-frontenginxconf)
6. [ API-urile (Dockerfile) ](#6-api-urile-dockerfile)

---

## 1. docker-compose.yml

```yaml
# =============================================================================
# AstroLumina - Docker Compose
# Traefik = routing + SSL | Nginx = frontend static | Express = APIs
# =============================================================================

services:
```

**Ce este**: Fișierul principal care definește TOATE containerele și relațiile dintre ele.

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Traefik - Reverse Proxy + SSL (Let's Encrypt)
# ─────────────────────────────────────────────────────────────────────────────
traefik:
```

**Ce este**: Serviciul Traefik - reverse proxy care face routing între containere.

```yaml
image: traefik:v3.1
```

**Ce face**: Folosește imaginea oficială Traefik v3.1 din Docker Hub.
**De ce**: Nu trebuie să construim noi imaginea.

```yaml
container_name: astrolumina-traefik
```

**Ce face**: Numele containerului (vizibil în `docker ps`).
**De ce**: Ușor de identificat în logs/monitoring.

```yaml
restart: unless-stopped
```

**Ce face**: Auto-restart dacă containerul crapa sau serverul repornește.
**De ce**: Disponibilitate automată fără intervenție manuală.

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro # Docker socket - pentru service discovery
  - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro # Config static
  - ./traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro # Config dinamic (middleware)
  - ./traefik/certs:/certs:ro # Certificate SSL (auto-generated)
  - ./traefik/logs:/var/log/traefik # Loguri
```

**Ce face**: **Volume** = foldere partajate între calculatorul gazdă și container.

| Volum                  | Scop                                      |
| ---------------------- | ----------------------------------------- |
| `/var/run/docker.sock` | Docker API - Traefik descoperă containere |
| `traefik.yml`          | Config Traefik (read-only)                |
| `dynamic.yml`          | Middleware adițional                      |
| `/certs`               | Certificate Let's Encrypt                 |
| `/var/log/traefik`     | Loguri                                    |

`:ro` = read-only (containerul poate citi, nu scrie).

```yaml
networks:
  - astrolumina
```

**Ce face**: Conectează containerul la rețeaua Docker dedicată.
**De ce**: Containerele comunică între ele prin această rețea, nu direct.

```yaml
ports:
  - "80:80" # HTTP
  - "443:443" # HTTPS
  - "8080:8080" # Traefik Dashboard
```

**Ce face**: **Port mapping** = `gazdă:container`.

| Port Gazdă | Port Container | Serviciu          |
| ---------- | -------------- | ----------------- |
| 80         | 80             | HTTP (Traefik)    |
| 443        | 443            | HTTPS (Traefik)   |
| 8080       | 8080           | Traefik Dashboard |

**NOTĂ**: Porturile sunt pe gazdă (calculatorul tău), nu în container.

```yaml
environment:
  - TZ=Europe/Bucharest
```

**Ce face**: Setează timezone pentru loguri.
**De ce**: Logurile să fie în ora ta.

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`traefik.localhost\`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls=true"
```

**Ce face**: **Labels** = instrucțiuni pentru Traefik să descopere containerul.

| Label                            | Ce face                                              |
| -------------------------------- | ---------------------------------------------------- |
| `traefik.enable=true`            | -activează serviciul în Traefik                      |
| `dashboard.rule=Host(...)`       | Condiție routing (când hostname e traefik.localhost) |
| `dashboard.service=api@internal` | Folosește API intern Traefik                         |
| `entrypoints=websecure`          | Folosește HTTPS                                      |
| `tls=true`                       | Enable TLS                                           |

---

### Frontend Service

```yaml
frontend:
  build:
    context: ./AstroLumina-Frontend
    dockerfile: Dockerfile
```

**Ce face**: Build image din Dockerfile local (nu imagine pre-compilată).

| Parametru    | Scop                    |
| ------------ | ----------------------- |
| `context`    | Folder-ul cu Dockerfile |
| `dockerfile` | Numele fișierului       |

```yaml
expose:
  - "80"
```

**Ce face**: Expune portul 80 către alte containere (NU către gazdă).
**NOTĂ**: `expose` ≠ `ports`. `expose` e intern, `ports` e extern.

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(\`astrolumina.localhost\`)"
      - "traefik.http.routers.frontend.entrypoints=web,websecure"
      - "traefik.http.services.frontend.loadbalancer.server.port=80"
      - "traefik.http.routers.frontend.tls=true"
```

| Label                              | Ce face                                     |
| ---------------------------------- | ------------------------------------------- |
| `rule=Host(astrolumina.localhost)` | Când cineva accesează astrolumina.localhost |
| `entrypoints=web,websecure`        | Atât HTTP cât și HTTPS                      |
| `server.port=80`                   | Portul din containerul Frontend             |
| `tls=true`                         | Enable TLS                                  |

---

### AstrologyAPI Service

```yaml
astrology-api:
  build:
    context: ./AstroLumina-AstrologyAPI
    dockerfile: Dockerfile
  container_name: astrolumina-astrology-api
  restart: unless-stopped

  expose:
    - "3031"

  environment:
    - NODE_ENV=production
    - PORT=3031
    - ASTROLOGER_API_KEY=${ASTROLOGER_API_KEY}
    - ASTROLOGER_API_URL=https://astrology-api.p.rapidapi.com
    - CORS_ORIGINS=https://astrolumina.com,https://www.astrolumina.com
    - SENTRY_DSN=${SENTRY_DSN}
```

**Ce face**: Variabile de mediu (env vars).

| Variabilă            | Scop                 | Exemplu     |
| -------------------- | -------------------- | ----------- |
| `NODE_ENV`           | Modul de funcționare | production  |
| `PORT`               | Portul serverului    | 3031        |
| `ASTROLOGER_API_KEY` | Cheie API externă    | (din .env)  |
| `CORS_ORIGINS`       | Origini permise      | https://... |
| `SENTRY_DSN`         | Monitoring Sentry    | (din .env)  |

`${VARIABILA}` = citește din fișierul .env.

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.astrology.rule=Host(\`api.astrolumina.com\`) && PathPrefix(\`/astrology\`)"
      - "traefik.http.routers.astrology.entrypoints=websecure"
      - "traefik.http.services.astrology.loadbalancer.server.port=3031"
      - "traefik.http.middlewares.astrology-stripprefix.stripprefix.prefix=/astrology"
      - "traefik.http.routers.astrology.tls=true"
```

| Label                                      | Ce face                                                    |
| ------------------------------------------ | ---------------------------------------------------------- |
| `rule=Host(...) && PathPrefix(/astrology)` | Routing: api.astrolumina.com/astrology/\*                  |
| `stripprefix.prefix=/astrology`            | Șterge /astrology din path înainte să trimită la container |

**Exemplu**: `/astrology/horoscope` → container primește `/horoscope`

---

### Rețea

```yaml
networks:
  astrolumina:
    driver: bridge
    name: astrolumina-network
```

**Ce face**: Definește rețeaua privată pentru containere.

| Parametru        | Scop                   |
| ---------------- | ---------------------- |
| `driver: bridge` | Driver standard Docker |
| `name`           | Numele rețelei         |

**NOTĂ**: Rețeaua e creată automat de docker compose.

---

## 2. traefik/traefik.yml

```yaml
# =============================================================================
# Traefik Configuration
# Traefik v3 cu Let's Encrypt
# =============================================================================

global:
  checkNewVersion: true # Verifică update-uri la pornire
  sendAnonymousUsage: false # NU trimite date anonime
```

```yaml
log:
  level: INFO # DEBUG, INFO, WARN, ERROR
  filePath: /var/log/traefik/traefik.log
  format: json # json sau common
```

```yaml
accessLog:
  filePath: /var/log/traefik/access.log
  format: json
```

```yaml
api:
  dashboard: true # Activează dashboard
  insecure: true # Fără auth (doar pentru dezvoltare!)
```

**ATENȚIE**: `insecure: true` = oricine poate accesa dashboard. În producție, pune auth.

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

**Ce face**: Redirect HTTP → HTTPS automat.

| Parametru                               | Scop                     |
| --------------------------------------- | ------------------------ |
| `address: ":80"`                        | Listen pe portul 80      |
| `redirections.entryPoint.to: websecure` | Spre HTTPS               |
| `scheme: https`                         | Folosește HTTPS          |
| `permanent: true`                       | 301 redirect (permanent) |

```yaml
websecure:
  address: ":443"
  http:
    tls:
      certResolver: letsencrypt
```

**Ce face**: HTTPS cu TLS automat prin Let's Encrypt.

```yaml
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: astrolumina-network

  file:
    directory: /etc/traefik/dynamic.yml
    watch: true
```

**Ce face**: **Providers** = surse de configurare.

| Provider | Scop                          |
| -------- | ----------------------------- |
| `docker` | Citește labels din containere |
| `file`   | Citește config dinamic        |

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@astrolumina.com
      storage: /certs/acme.json
      httpChallenge:
        entryPoint: web
      caServer: https://acme-v02.api.letsencrypt.org/directory
```

**Ce face**: Let's Encrypt pentru SSL automat.

| Parametru       | Scop                        |
| --------------- | --------------------------- |
| `email`         | Email pentru notificări     |
| `storage`       | Unde salvează certurile     |
| `httpChallenge` | Verifică domeniul prin HTTP |
| `caServer`      | Server LE pentru producție  |

---

## 3. traefik/dynamic.yml

```yaml
http:
  middlewares:
    compress:
      compress: {}
```

**Ce face**: Comprimă răspunsurile gzip.

```yaml
security-headers:
  headers:
    frameDeny: true # Previne clickjacking
    contentTypeNosniff: true # Previne MIME sniffing
    browserXssFilter: true # Protecție XSS vechi
    referrerPolicy: "strict-origin-when-cross-origin"
    customResponseHeaders:
      X-Robots-Tag: "noindex, nofollow"
```

**Ce face**: Headers de securitate (OWASP).

```yaml
rate-limit:
  rateLimit:
    average: 100 # 100 cereri
    burst: 50 # peak de 50
    period: 1s # pe secundă
```

**Ce face**: Rate limiting împotriva atacurilor.

---

## 4. AstroLumina-Frontend/Dockerfile

```dockerfile
# =============================================================================
# AstroLumina Frontend - Dockerfile cu Nginx
# =============================================================================

FROM node:22-alpine AS builder
```

**Ce face**: **Stage 1** - Build aplicația React.

| Parte            | Scop                       |
| ---------------- | -------------------------- |
| `node:22-alpine` | Node.js 22 pe Alpine Linux |
| `AS builder`     | Numele stage-ului          |

```dockerfile
WORKDIR /app
```

**Ce face**: Setează directorul de lucru (cd /app).

```dockerfile
COPY package.json package-lock.json ./
```

**Ce face**: Copiază fișierele de dependențe.
**De ce**: Separat pentru cache - modificări la cod nu re-instală pachete.

```dockerfile
RUN npm ci
```

**Ce face**: Instalează TOATE dependențele (exact ca package-lock.json).

```dockerfile
COPY . .
```

**Ce face**: Copiază restul fișierelor sursă.

```dockerfile
RUN npm run build
```

**Ce face**: Compilează React → fișiere statice în `dist/`.

```dockerfile
FROM nginx:alpine AS runner
```

**Ce face**: **Stage 2** - Nginx pentru servire statică.

```dockerfile
COPY nginx.conf /etc/nginx/nginx.conf
```

**Ce face**: Copiază config Nginx custom.

```dockerfile
COPY --from=builder /app/dist /usr/share/nginx/html
```

**Ce face**: Ia `dist` din stage-ul builder și îl pune în Nginx.
`--from=builder` = referință la stage-ul anterior.

```dockerfile
RUN chown -R nginx:nginx /usr/share/nginx/html
```

**Ce face**: Schimbă owner la nginx (non-root user).

```dockerfile
USER nginx
```

**Ce face**: Rulează containerul ca user nginx, nu root.
**Security**: Dacă e compromis, are acces limitat.

```dockerfile
EXPOSE 80
```

**Ce face**: Documentează portul 80 (nu mapează efectiv).

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1
```

**Ce face**: Health check - verifică dacă serverul e alive.

| Parametru        | Scop                                    |
| ---------------- | --------------------------------------- |
| `--interval`     | Cât de des verifică                     |
| `--timeout`      | Timeout per verificare                  |
| `--start-period` | Așteaptă la pornire                     |
| `--retries`      | Încercări înainte să marcheze unhealthy |
| `wget --spider`  | Verifică fără să downloadeze            |

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

**Ce face**: Pornește Nginx în foreground (nu background).

`-g` = pass directivă globală.
`daemon off` = Nginx nu se detașează (rulează în foreground).

---

## 5. AstroLumina-Frontend/nginx.conf

```nginx
events {
    worker_connections 1024;
}
```

**Ce face**: Maximum 1024 conexiuni simultane per worker.

```nginx
http {
    include       /etc/nginx/mime.types;
    default_type application/octet-stream;
```

**Ce face**: Definește tipuri MIME pentru fișiere.

```nginx
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
```

**Ce face**: Logging config.

```nginx
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
```

**Ce face**: Optimizări pentru performanță.

```nginx
    keepalive_timeout 65;
    keepalive_requests 100;
```

**Ce face**: Keep-alive settings.

```nginx
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json
               application/javascript application/rss+xml
               application/atom+xml image/svg+xml;
```

**Ce face**: Gzip compression.

```nginx
    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;
```

**Ce face**: Server block principal.

```nginx
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

**Ce face**: Security headers pe fiecare răspuns.

```nginx
        location ~* \.(js|css|png|jpg|jpeg|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
```

**Ce face**: Cache static assets 1 an.

```nginx
        location ~* \.html$ {
            add_header Cache-Control "no-cache";
        }
```

**Ce face**: HTML nu e cache-uit.

```nginx
        location / {
            try_files $uri $uri/ /index.html;
        }
```

**Ce face**: **SPA Fallback** - React Router.

| Ce face       | Exemplu           |
| ------------- | ----------------- |
| `$uri`        | Cerere directă    |
| `$uri/`       | Încearcă cu /     |
| `/index.html` | Fallback la index |

`/about` → nu există → servește `/index.html` → React Router face routing.

```nginx
        location /health {
            access_log off;
            return 200 "OK";
            add_header Content-Type text/plain;
        }
```

**Ce face**: Health check endpoint.

---

## 6. API-urile (Dockerfile)

Pattern identic pentru toate 3 API-uri:

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --only=production
```

**Stage 1**: Instalează doar dependencies (NU devDependencies).

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build
```

**Stage 2**: Compilează TypeScript → JavaScript.

```dockerfile
FROM node:22-alpine AS runner
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs
```

**Stage 3**: Creează user non-root.

```dockerfile
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
COPY --from=builder /app/config ./config
COPY --from=builder /app/middleware ./middleware
COPY --from=builder /app/routes ./routes
COPY --from=builder /app/translations ./translations
COPY --from=builder /app/types ./types
COPY --from=builder /app/instrument.js ./
COPY --from=builder /app/constants.js ./
```

**Copiază**: node_modules (deps) + compiled code (builder).

```dockerfile
ENV NODE_ENV=production
ENV PORT=3031
```

**Setează**: Variabile de mediu default.

```dockerfile
RUN chown -R nodejs:nodejs /app
USER nodejs
```

**Security**: Rulează ca non-root.

```dockerfile
EXPOSE 3031
CMD ["node", "dist/server.js"]
```

**Pornește**: Serverul Express.

---

## Sumar Arhitectură

```
┌─────────────────────────────────────────────────┐
│                  GAZDĂ (localhost)              │
│                                                 │
│  Port 80 ──┐                                    │
│  Port 443 ─┤                                    │
│  Port 8080 ┘                                    │
└────────────┬────────────────────────────────────┘
             │
             ▼
     ┌───────────────┐
     │   Traefik    │ Reverse Proxy + SSL
     │  (port 80)   │ Let's Encrypt
     └───────┬───────┘
             │
    ┌────────┼────────┬────────┬────────┐
    │        │        │        │        │
    ▼        ▼        ▼        ▼        ▼
┌────────┐┌──────┐┌──────┐┌───────┐┌───────┐
│Frontend││Astrol ││Bookings││Payment││Dashboard│
│Nginx  ││API   ││API   ││API   ││Traefik│
│:80    ││:3031 ││:3033 ││:3032 ││:8080 │
└────────┘└──────┘└──────┘└───────┘└───────┘
    │        │        │        │
    └────────┴────────┴────────┘
         Rețea Docker
       astrolumina-network
```

---

## Run

```bash
# 1. Variabile de mediu
cp .env.example .env
# Editează .env cu cheile Tale

# 2. Build
docker compose build

# 3. Run
docker compose up -d

# 4. Verifică
docker compose ps

# 5. Logs
docker compose logs -f

# 6. Stop
docker compose down
```

---

## Troubleshooting

| Problemă              | Soluție                             |
| --------------------- | ----------------------------------- |
| Container nu pornește | `docker compose logs <serviciu>`    |
| Nu se networking      | Verifică labels Traefik             |
| SSL nu merge          | Verifică `/certs/acme.json`         |
| Frontend 404          | Verifică SPA fallback în nginx.conf |
| CORS error            | Verifică `CORS_ORIGINS` env         |

---

## Fișiere Create

```
AstroLumina/
├── docker-compose.yml
├── .env.example
├── traefik/
│   ├── traefik.yml
│   ├── dynamic.yml
│   ├── certs/
│   └── logs/
├── AstroLumina-Frontend/
│   ├── Dockerfile
│   └── nginx.conf
├── AstroLumina-AstrologyAPI/
│   └── Dockerfile
├── AstroLumina-BookingAPI/
│   └── Dockerfile
└── AstroLumina-PaymentAPI/
    └── Dockerfile
```
