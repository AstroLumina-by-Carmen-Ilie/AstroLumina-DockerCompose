# AstroLumina-DevOps

Documentație și instrumente pentru AstroLumina.

## Docker Infrastructure

Containerize cu Traefik reverse proxy + Let's Encrypt SSL.

### Servicii

| Serviciu | Port | URL |
|----------|------|-----|
| Frontend | 80 | http://astrolumina.localhost |
| AstrologyAPI | 3031 | /astrology/* |
| BookingAPI | 3033 | /bookings/* |
| PaymentAPI | 3032 | /payment/* |
| Traefik Dashboard | 8080 | http://traefik.localhost:8080 |

### Run

```bash
# 1. Variabile de mediu
cp .env.example .env

# 2. Build + Start
docker compose up --build -d

# 3. Verifică
docker compose ps
docker compose logs -f

# 4. Stop
docker compose down
```

### Test

```bash
curl http://localhost
curl http://localhost:3031/health
curl http://localhost:3033/health
curl http://localhost:3032/health
```

### Referințe

- DOCUMENTATION.md - Documentație tehnică detaliată
- traefik/traefik.yml - Config Traefik
- traefik/dynamic.yml - Middleware
