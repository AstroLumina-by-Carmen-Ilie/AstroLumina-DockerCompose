# AstroLumina — Docker Infrastructure

Docker Compose infrastructure for AstroLumina across three environments:
**development**, **staging**, and **production**. Application images are pulled
from GHCR (`ghcr.io/astrolumina-by-carmen-ilie`) — this repo contains only
orchestration: compose files, Traefik configs, env templates, and deploy workflows.

## Table of contents

1. [Repository layout](#1-repository-layout)
2. [Environments at a glance](#2-environments-at-a-glance)
3. [Architecture](#3-architecture)
4. [Services](#4-services)
5. [Traefik: static vs dynamic config](#5-traefik-static-vs-dynamic-config)
6. [Request flow](#6-request-flow)
7. [Blue-green deployments](#7-blue-green-deployments)
8. [CI/CD](#8-cicd)
9. [Configuration reference](#9-configuration-reference)
10. [Runbooks](#10-runbooks)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Repository layout

```mermaid
graph TD
    ROOT["AstroLumina-DockerCompose/"]
    ROOT --> DEV["development/"]
    ROOT --> STG["staging/"]
    ROOT --> PRD["production/"]
    ROOT --> GH[".github/workflows/"]
    ROOT --> SH["refresh.sh"]

    DEV --> DEV_C["docker-compose.yml<br/>4 services, direct ports,<br/>replicas: 1, no Traefik"]
    DEV --> DEV_E[".env.example"]

    STG --> STG_C["docker-compose.yml<br/>Traefik only (:80 + :8080)"]
    STG --> STG_B["docker-compose.blue.yml<br/>4 × *-blue services"]
    STG --> STG_G["docker-compose.green.yml<br/>4 × *-green services"]
    STG --> STG_T["traefik/<br/>traefik.yml + dynamic/routes.yml"]
    STG --> STG_E[".env.example"]

    PRD --> PRD_C["docker-compose.yml<br/>Traefik only (:80 + :443 + :8080)"]
    PRD --> PRD_B["docker-compose.blue.yml<br/>4 × *-blue services"]
    PRD --> PRD_G["docker-compose.green.yml<br/>4 × *-green services"]
    PRD --> PRD_T["traefik/<br/>traefik.yml + dynamic/routes.yml"]
    PRD --> PRD_E[".env.example<br/>+ TRAEFIK_DASHBOARD_AUTH"]

    GH --> GH_S["deploy-staging.yml<br/>dispatch: deploy-staging"]
    GH --> GH_P["deploy-production.yml<br/>dispatch: deploy-production"]
```

Each environment directory is self-contained: `cd` into it and run
`docker compose` there. The `.env` files are gitignored and contain secrets —
never commit them.

---

## 2. Environments at a glance

| Aspect | Development | Staging | Production |
|---|---|---|---|
| Compose files | `docker-compose.yml` | `docker-compose.yml` + `.blue.yml` + `.green.yml` | `docker-compose.yml` + `.blue.yml` + `.green.yml` |
| Reverse proxy | None (direct ports) | Traefik `:80` + dashboard `:8080` | Traefik `:80` + `:443` + dashboard `:8080` |
| TLS | No | No (HTTP only) | Yes (Let's Encrypt `httpChallenge`) |
| Replicas | 1 | 3 per service | 3 per service |
| Network | `astrolumina-dev` | `astrolumina-staging` | `astrolumina-production` |
| Host | `localhost` ports | `staging.astrolumina.ro` | `astrolumina.ro` |
| Dashboard | None | Open on `:8080` (`insecure: true`) | `dashboard.astrolumina.ro` + basic auth |
| Deploy | Manual | `deploy-staging.yml` via SSH | `deploy-production.yml` via SSH |

---

## 3. Architecture

### 3.1 Development — direct ports, no proxy

Four containers on one bridge network, each publishing its port to the host.
The frontend depends on the three APIs (`depends_on`).

```mermaid
flowchart LR
    subgraph HOST["Host machine"]
        B1["${FRONTEND_SERVER_PORT}"]
        B2["${ASTROLOGY_API_SERVER_PORT}"]
        B3["${BOOKING_API_SERVER_PORT}"]
        B4["${PAYMENT_API_SERVER_PORT}"]
    end

    subgraph NET["network: astrolumina-dev"]
        FE["frontend<br/>image: astrolumina-frontend<br/>:80 → host port<br/>2 CPU / 2G"]
        AA["astrology-api<br/>:3031<br/>1 CPU / 1G"]
        BA["booking-api<br/>:3033<br/>1 CPU / 1G"]
        PA["payment-api<br/>:3032<br/>1 CPU / 1G"]
    end

    B1 --> FE
    B2 --> AA
    B3 --> BA
    B4 --> PA
    FE -.->|"depends_on"| AA
    FE -.->|"depends_on"| BA
    FE -.->|"depends_on"| PA
```

### 3.2 Staging — Traefik (HTTP) + blue-green

Traefik is the only container with published ports. The blue and green stacks
run side by side (`expose` only, no `ports`); Traefik routes all traffic to
whichever color is **LIVE** in `traefik/dynamic/routes.yml`.

```mermaid
flowchart TB
    NET["Internet<br/>staging.astrolumina.ro :80"]

    subgraph HOST["Staging host — network: astrolumina-staging"]
        TR["Traefik v3.1<br/>:80 + :8080 dashboard<br/>file provider, watch: true"]

        subgraph BLUE["BLUE stack (LIVE) — replicas: 3"]
            FB["frontend-blue :80"]
            AB["astrology-api-blue :3031"]
            BB["booking-api-blue :3033"]
            PB["payment-api-blue :3032"]
        end

        subgraph GREEN["GREEN stack (idle) — replicas: 3"]
            FG["frontend-green :80"]
            AG["astrology-api-green :3031"]
            BG["booking-api-green :3033"]
            PG["payment-api-green :3032"]
        end
    end

    NET --> TR
    TR ==>|"service: *-blue"| FB & AB & BB & PB
    TR -.->|"idle, no traffic"| FG & AG & BG & PG
```

### 3.3 Production — Traefik (HTTPS) + blue-green

Same shape as staging, plus: `:443` with automatic Let's Encrypt certificates,
HTTP→HTTPS redirect, and an auth-protected dashboard on its own host.

```mermaid
flowchart TB
    NET["Internet<br/>astrolumina.ro :80/:443<br/>dashboard.astrolumina.ro :443"]

    subgraph HOST["Production host — network: astrolumina-production"]
        TR["Traefik v3.1<br/>:80 redirect + ACME challenge<br/>:443 TLS (letsencrypt)<br/>:8080 · dashboard via websecure"]

        subgraph BLUE["BLUE stack (LIVE) — replicas: 3"]
            FB["frontend-blue :80"]
            AB["astrology-api-blue :3031"]
            BB["booking-api-blue :3033"]
            PB["payment-api-blue :3032"]
        end

        subgraph GREEN["GREEN stack (idle) — replicas: 3"]
            FG["frontend-green :80"]
            AG["astrology-api-green :3031"]
            BG["booking-api-green :3033"]
            PG["payment-api-green :3032"]
        end
    end

    NET --> TR
    TR ==>|"websecure + certResolver"| FB & AB & BB & PB
    TR -.->|"idle, no traffic"| FG & AG & BG & PG
```

---

## 4. Services

All four application services share the same structure in every environment;
only names, ports/publish mode, and replica counts differ.

| Service | Image (GHCR) | Container port | Dev publish | Staging/Prod |
|---|---|---|---|---|
| `frontend` | `astrolumina-frontend` | 80 | `${FRONTEND_SERVER_PORT}:80` | `expose: 80` (Traefik only) |
| `astrology-api` | `astrolumina-astrologyapi` | 3031 | `${ASTROLOGY_API_SERVER_PORT}:3031` | `expose: 3031` |
| `booking-api` | `astrolumina-bookingapi` | 3033 | `${BOOKING_API_SERVER_PORT}:3033` | `expose: 3033` |
| `payment-api` | `astrolumina-paymentapi` | 3032 | `${PAYMENT_API_SERVER_PORT}:3032` | `expose: 3032` |

Resource budgets (identical in all environments):

| Service | Limits | Reservations |
|---|---|---|
| frontend | 2 CPU / 2G RAM | 0.5 CPU / 512M RAM |
| each API | 1 CPU / 1G RAM | 0.125 CPU / 128M RAM |

> **Memory units:** this repo uses `G`/`M` (e.g. `memory: 2G`). Docker Compose
> interprets these as **1024-based** (2G = 2147483648 bytes — verified via
> `docker compose config`). Note this differs from Kubernetes, where `G`/`M`
> are decimal (1000-based) and you would need `Gi`/`Mi` for the same values.

Every service pulls on every start (`pull_policy: always`), restarts
automatically (`restart: unless-stopped`), and has a `wget --spider`
healthcheck (5m interval, 10s timeout, 3 retries, 40s start period).

---

## 5. Traefik: static vs dynamic config

```mermaid
flowchart LR
    subgraph STATIC["Static config — traefik/traefik.yml<br/>(requires Traefik restart to change)"]
        EP["entryPoints<br/>staging: web :80<br/>prod: web :80 + websecure :443"]
        API["api.dashboard<br/>staging insecure: true<br/>prod insecure: false"]
        PROV["providers.file<br/>routes.yml, watch: true"]
        ACME["certificatesResolvers<br/>prod only: letsencrypt httpChallenge"]
    end

    subgraph DYNAMIC["Dynamic config — traefik/dynamic/routes.yml<br/>(auto-reload, no restart)"]
        MW["middlewares<br/>security-headers · compress<br/>rate-limit · strip-*"]
        RO["routers<br/>Host + PathPrefix rules"]
        SV["services<br/>*-blue and *-green<br/>loadBalancer URLs"]
    end

    STATIC --> DYNAMIC
    RO -->|"service: points to<br/>LIVE color"| SV
    MW -->|"applied per router"| RO
```

Key differences between staging and production static config:

| Setting | Staging `traefik.yml` | Production `traefik.yml` |
|---|---|---|
| Entrypoints | `web: :80` only | `web: :80` + `websecure: :443` |
| Dashboard API | `insecure: true` (open `:8080`) | `insecure: false` (via router + basic auth) |
| ACME resolver | None | `letsencrypt` (`httpChallenge` on `web`, storage `/certs/acme.json`) |
| Logs | JSON `traefik.log` + `access.log` | Same |

The dynamic `routes.yml` defines, per router: entrypoints, a
`Host(...) && PathPrefix(...)` rule, the middleware chain, and the `service:`
field that selects the **LIVE** color. Production additionally has a
`catch-http` router (`to-https` redirect), `tls.certResolver: letsencrypt` on
every router, and a `dashboard-auth` basic-auth middleware fed by
`${TRAEFIK_DASHBOARD_AUTH}` (generate with `htpasswd -nb admin PASSWORD`).

---

## 6. Request flow

How a request travels through Traefik to a backend (example: horoscope call).

```mermaid
sequenceDiagram
    participant C as Client
    participant T as Traefik
    participant MW as Middleware chain
    participant S as LIVE backend<br/>(e.g. astrology-api-blue:3031)

    C->>T: GET staging.astrolumina.ro/api/astrology/horoscope
    T->>T: Router match: Host + PathPrefix(`/api/astrology`)
    T->>MW: 1. security-headers (OWASP headers + noindex)
    MW->>MW: 2. compress (gzip)
    MW->>MW: 3. rate-limit (100 avg / 50 burst / 1s)
    MW->>MW: 4. strip-astrology (remove /api/astrology prefix)
    MW->>S: GET /horoscope
    S-->>C: JSON response (via Traefik)
```

API path mapping (same in staging and production, minus TLS):

| Public path | Middleware strips | Backend receives |
|---|---|---|
| `/api/astrology/*` | `/api/astrology` | `http://astrology-api-<color>:3031/*` |
| `/api/booking/*` | `/api/booking` | `http://booking-api-<color>:3033/*` |
| `/api/payment/*` | `/api/payment` | `http://payment-api-<color>:3032/*` |
| `/` (everything else) | — | `http://frontend-<color>:80` |

---

## 7. Blue-green deployments

Both app stacks always run; the switch is a **4-line edit** in
`traefik/dynamic/routes.yml` — Traefik reloads it automatically (`watch: true`),
no restart, near-zero downtime.

```mermaid
flowchart TD
    START["New version released<br/>(fresh image tag in GHCR)"]
    DEPLOY["Deploy new tag to the IDLE color<br/>e.g. green is idle → update *-green"]
    HEALTH["Healthcheck the idle stack directly<br/>container IPs or internal curl"]
    DECIDE{"Green healthy?"}
    SWITCH["Flip the 4 × service: fields<br/>*-blue → *-green in routes.yml"]
    RELOAD["Traefik auto-reloads (watch: true)<br/>traffic moves to green"]
    VERIFY["Smoke-test public Host<br/>frontend + /api/* health"]
    KEEP["Keep blue running as instant rollback"]
    ROLLBACK["Flip back: *-green → *-blue"]

    START --> DEPLOY --> HEALTH --> DECIDE
    DECIDE -- "yes" --> SWITCH --> RELOAD --> VERIFY --> KEEP
    DECIDE -- "no" --> DEPLOY
    VERIFY -- "broken" --> ROLLBACK
```

The four fields (staging example; production identical except host/TLS):

```yaml
service: astrology-blue # LIVE: change to astrology-green to switch
service: booking-blue   # LIVE: change to booking-green to switch
service: payment-blue   # LIVE: change to payment-green to switch
service: frontend-blue  # LIVE: change to frontend-green to switch
```

Rollback is the same edit in reverse — the old color keeps running until you
take it down, so recovery is one edit away.

---

## 8. CI/CD

```mermaid
flowchart LR
    APP["App repo<br/>(Frontend / *API)<br/>image published to GHCR"] -->|repository_dispatch<br/>+ manual trigger| WF["This repo: deploy workflow<br/>(staging / production)"]
    WF --> SSH["SSH into env host<br/>(appleboy/ssh-action)"]
    SSH --> MAP["Map image name → .env variable<br/>+ blue/green services"]
    MAP --> SED["Pin tag in .env<br/>(verified with grep)"]
    SED --> PULL["compose pull + up -d<br/>(all 3 -f files)"]
    PULL --> SMOKE["Smoke test via Traefik<br/>(retry 12 × 10s)"]
```

**Dispatch contract** — app repos trigger a deploy by sending a
`repository_dispatch` event to this repo (needs a token with `repo` scope):

| Event type | Workflow | Target host |
|---|---|---|
| `deploy-staging` | `deploy-staging.yml` | staging |
| `deploy-production` | `deploy-production.yml` | production |

Payload (`client_payload`), or the equivalent `workflow_dispatch` inputs
for manual runs from the Actions tab:

```json
{
  "service": "astrolumina-frontend",
  "tag": "v1.4.2"
}
```

Valid `service` values (= GHCR image names): `astrolumina-frontend`,
`astrolumina-astrologyapi`, `astrolumina-bookingapi`, `astrolumina-paymentapi`.
Each maps to its `*_DOCKER_IMAGE_TAG` variable in `<env>/.env` and to the
matching `-blue`/`-green` compose services, which are pulled and recreated.
Both colors get the new tag; the blue-green switch itself stays manual
(see [section 7](#7-blue-green-deployments)).

**Required secrets** (per environment): `STAGING_HOST` / `PRODUCTION_HOST`
plus `STAGING_SSH_KEY` / `PRODUCTION_SSH_KEY`.

- `refresh.sh` (repo root) — local helper that runs `docker compose down`
  across the four app repos via Doppler; unrelated to server deploys.

---

## 9. Configuration reference

- **Env files:** copy `<env>/.env.example` to `<env>/.env` and fill in values.
  Every app variable (`*_PORT`, `*_DNS`, `*_SENTRY_DSN`, Stripe keys, R2/D1,
  Resend, CalCom, RapidAPI astrologer key) flows into the containers via
  `environment:`. `${VAR}` interpolation means a missing `.env` breaks
  `docker compose config` — that is expected, not a bug.
- **Production extra:** `TRAEFIK_DASHBOARD_AUTH` holds an `htpasswd`-generated
  `admin:<hash>` pair (keep the quotes in `.env`).
- **Networks:** one dedicated bridge per environment (`astrolumina-dev` /
  `-staging` / `-production`). Blue, green, and Traefik all share their env's
  network so Traefik reaches backends by service name (e.g.
  `http://frontend-blue:80`).
- **Only Traefik publishes ports** in staging/production. If an app service
  ever shows up under `ports:` there, that's a mistake — app services use
  `expose:` (container-network only).

---

## 10. Runbooks

```bash
# ── Development ─────────────────────────────────────────────
cd development
cp .env.example .env          # then fill in values
docker compose up --build -d
docker compose ps
curl http://localhost:${FRONTEND_SERVER_PORT}
curl http://localhost:${ASTROLOGY_API_SERVER_PORT}/health

# ── Staging / Production (Traefik + blue + green) ───────────
cd staging                    # or: production
cp .env.example .env          # then fill in values
docker compose -f docker-compose.yml \
               -f docker-compose.blue.yml \
               -f docker-compose.green.yml up -d
docker compose ps

# Verify routing
curl http://staging.astrolumina.ro            # staging (HTTP)
curl https://astrolumina.ro/api/astrology/health  # production (HTTPS)

# Validate config without starting anything
docker compose config | grep -E "replicas|memory|cpus"
```

**Switch LIVE color** (staging example): edit the four `service:` fields in
`staging/traefik/dynamic/routes.yml`, save, then verify — no restart needed:

```bash
curl http://staging.astrolumina.ro/api/astrology/health
curl http://staging.astrolumina.ro/api/booking/health
curl http://staging.astrolumina.ro/api/payment/health
curl http://staging.astrolumina.ro
```

---

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `docker compose config` fails on missing variable | No `.env` file yet | Copy `.env.example` → `.env` and fill values |
| Container won't start | Image tag wrong / secret missing | `docker compose logs <service>` |
| 404 via Traefik, direct container OK | Router rule or `service:` typo in `routes.yml` | Check rules; Traefik dashboard `:8080` shows active routers |
| API gets `/api/astrology/...` unprefixed 404 | Missing `strip-*` middleware on router | Add `strip-astrology`/`strip-booking`/`strip-payment` |
| No HTTPS in production | ACME challenge failing | Check `/certs/acme.json` exists; port 80 reachable for `httpChallenge` |
| Dashboard asks for password (prod) | Expected — basic auth | Use credentials matching `TRAEFIK_DASHBOARD_AUTH` |
| CORS errors | `*_URL` / DNS vars mismatch | Align env URLs with the public host |
| Switch didn't take effect | Edited wrong file or indentation broke YAML | Validate YAML; confirm `watch: true` in `traefik.yml` |
