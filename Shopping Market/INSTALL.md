# 🛒 Market Fresh — Full System Installation Guide

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MARKET FRESH SYSTEM                     │
├──────────────┬──────────────┬──────────────┬────────────────┤
│ Customer App │  Driver App  │ Admin Dashboard │   Backend    │
│  (Flutter)  │  (Flutter)   │   (React/Vite)  │  (Django)    │
│  iOS/Android │   Android   │  Browser/Web    │  REST + WS   │
└──────┬───────┴──────┬───────┴────────┬────────┴──────┬───────┘
       │              │                │               │
       └──────────────┴────────────────┴───────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   PostgreSQL DB   │
                    │   Redis Cache     │
                    │   Firebase FCM    │
                    │   Amazon S3       │
                    └───────────────────┘
```

---

## Prerequisites

- Ubuntu 22.04 LTS server (min 2 CPU, 4GB RAM, 40GB SSD)
- Docker & Docker Compose installed
- Domain name pointed to your server
- Firebase project created
- (Optional) AWS S3 bucket

---

## Step 1 — Server Setup

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose git curl
sudo usermod -aG docker $USER
newgrp docker
```

---

## Step 2 — Clone & Configure

```bash
# Upload project to server or clone from your git repo
cd /opt
git clone <your-repo-url> market-fresh
cd market-fresh

# Copy environment template
cp .env.example .env
nano .env
```

### Fill in your .env:
```env
SECRET_KEY=<generate-with: python -c "import secrets; print(secrets.token_urlsafe(50))">
DEBUG=False
ALLOWED_HOSTS=yourdomain.com,www.yourdomain.com
DB_PASSWORD=YourStrongPassword123!
FIREBASE_CREDENTIALS_PATH=firebase-credentials.json
GOOGLE_MAPS_API_KEY=your-google-maps-key
```

---

## Step 3 — Firebase Setup (Required for Push Notifications)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project → "Market Fresh"
3. Go to **Project Settings → Service Accounts**
4. Click **"Generate new private key"**
5. Download the JSON file
6. Place it in: `/opt/market-fresh/backend/firebase-credentials.json`

---

## Step 4 — Build & Start All Services

```bash
cd /opt/market-fresh

# Build and start everything
docker-compose up -d --build

# Check all services are running
docker-compose ps

# Watch logs
docker-compose logs -f backend
```

Expected output:
```
NAME                    STATUS
market-fresh-db-1       running
market-fresh-redis-1    running
market-fresh-backend-1  running
market-fresh-celery-1   running
market-fresh-admin-1    running
market-fresh-nginx-1    running
```

---

## Step 5 — Verify Backend & Initial Data

```bash
# Check migrations ran
docker-compose exec backend python manage.py showmigrations

# Initial data is auto-created on startup, verify:
docker-compose exec backend python manage.py shell -c "
from apps.users.models import User
from apps.products.models import Category
print('Admins:', User.objects.filter(role='admin').count())
print('Categories:', Category.objects.count())
"
```

---

## Step 6 — Access the System

| Service | URL | Credentials |
|---------|-----|-------------|
| Admin Dashboard | http://yourdomain.com | Phone: `01000000000` / Password: `Admin@123` |
| API Docs (Swagger) | http://yourdomain.com/api/docs/ | — |
| Django Admin | http://yourdomain.com/django-admin/ | same credentials |

> ⚠️ **IMPORTANT**: Change the default admin password immediately after first login!

---

## Step 7 — SSL Certificate (HTTPS)

```bash
sudo apt install -y certbot
sudo certbot certonly --standalone -d yourdomain.com -d www.yourdomain.com

# Copy certs
mkdir -p /opt/market-fresh/deployment/ssl
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem /opt/market-fresh/deployment/ssl/
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem /opt/market-fresh/deployment/ssl/

# Auto-renew
sudo crontab -e
# Add: 0 0 1 * * certbot renew --quiet
```

---

## Step 8 — Create First Super Admin in Dashboard

1. Login at http://yourdomain.com with default credentials
2. Navigate to **👑 إدارة المديرين (Admin Management)**
3. Click **"إنشاء مدير جديد"** (Create New Admin)
4. Fill 3-step wizard:
   - Step 1: Enter name, phone, password
   - Step 2: Choose role (Super Admin / Branch Manager / etc.)
   - Step 3: Assign branch access
5. New admin can login immediately

### Available Preset Roles:
| Role | Arabic | Permissions |
|------|--------|-------------|
| super_admin | مدير عام | Full access to everything |
| manager | مدير فرع | Orders, products, drivers, analytics |
| orders_staff | موظف طلبات | View & manage orders, assign drivers |
| products_staff | موظف منتجات | Add/edit products, categories, media |
| analytics_viewer | مشاهد تقارير | Read-only analytics & reports |
| custom | مخصص | Build your own permission set |

---

## Flutter App Installation

### Prerequisites
```bash
# Install Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"
flutter doctor
```

### Configure Backend URL
```bash
cd flutter_app
nano lib/utils/constants.dart
# Set: const String baseUrl = 'https://yourdomain.com/api/v1';
```

### Build Customer App (Android)
```bash
flutter build apk --release --flavor customer -t lib/main_customer.dart
# APK at: build/app/outputs/flutter-apk/app-customer-release.apk
```

### Build Driver App (Android)
```bash
flutter build apk --release --flavor driver -t lib/main_driver.dart
# APK at: build/app/outputs/flutter-apk/app-driver-release.apk
```

### Build iOS (Customer App)
```bash
flutter build ipa --release --flavor customer -t lib/main_customer.dart
# IPA at: build/ios/ipa/
```

---

## Payment Gateway Setup (Egypt)

### Paymob Integration
1. Register at [accept.paymob.com](https://accept.paymob.com)
2. Get your API key & Integration IDs
3. Add to `.env`:
```env
PAYMOB_API_KEY=your-api-key
PAYMOB_INTEGRATION_ID=your-integration-id
PAYMOB_IFRAME_ID=your-iframe-id
```

### Google Maps Setup
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Enable: Maps SDK for Android, Maps SDK for iOS, Places API, Directions API
3. Create API key → restrict to your app's package name
4. Add to `.env`: `GOOGLE_MAPS_API_KEY=your-key`

---

## Maintenance Commands

```bash
# View logs
docker-compose logs -f backend
docker-compose logs -f celery

# Restart specific service
docker-compose restart backend

# Database backup
docker-compose exec db pg_dump -U postgres market_fresh > backup_$(date +%Y%m%d).sql

# Database restore
cat backup.sql | docker-compose exec -T db psql -U postgres market_fresh

# Update & redeploy
git pull
docker-compose up -d --build backend admin_dashboard

# Clear Redis cache
docker-compose exec redis redis-cli FLUSHDB

# Run management command
docker-compose exec backend python manage.py <command>
```

---

## Environment Variables Reference

| Variable | Description | Required |
|----------|-------------|----------|
| `SECRET_KEY` | Django secret key (50+ chars) | ✅ Yes |
| `DEBUG` | False in production | ✅ Yes |
| `DB_PASSWORD` | PostgreSQL password | ✅ Yes |
| `FIREBASE_CREDENTIALS_PATH` | Path to Firebase JSON | ✅ Yes |
| `GOOGLE_MAPS_API_KEY` | Google Maps API key | ✅ Yes |
| `PAYMOB_API_KEY` | Paymob payment gateway | Optional |
| `USE_S3` | Enable AWS S3 for images | Optional |
| `AWS_ACCESS_KEY_ID` | AWS credentials | If USE_S3=True |

---

## Default Admin Credentials

```
Phone:    01000000000
Password: Admin@123
Role:     Super Admin (full access)
```

> ⚠️ Change this immediately via the dashboard Settings or Django Admin panel.

---

## Support

- API Documentation: `https://yourdomain.com/api/docs/`
- Admin Panel: `https://yourdomain.com`
- Backend health check: `https://yourdomain.com/api/v1/auth/register/` (should return 400, not 502)
