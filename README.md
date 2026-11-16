# Tashil Data Sharing Platform (منصة تسهيل لمشاركة بيانات التجزئة)

An enterprise retail data sharing and sell-out analytics platform built for FMCG manufacturers (Adeco, Unilever, PepsiCo) and Egyptian retail chains (Carrefour, Fathalla, Gomla Market, Spinneys).

## Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │    Executive Management Users (Adeco)   │
                      └───────────────────┬────────────────────┘
                                          │
                                          ▼
                      ┌────────────────────────────────────────┐
                      │       Flutter Web Desktop Portal       │
                      │  (M3 Design, Cairo RTL, Bento Grid,    │
                      │   Cascading Filters, Virtualized Table)│
                      └───────────────────┬────────────────────┘
                                          │  HTTPS / JWT (RLS)
                                          ▼
                      ┌────────────────────────────────────────┐
                      │       Go Cloud Run Backend Service     │
                      │  (Near-Zero Cold Start, High Concurrency│
                      │   Row-Level Security Multi-Tenancy)    │
                      └──────────────┬───────────────────┬─────┘
                                     │                   │
                     ┌───────────────▼────────┐   ┌──────▼──────────────┐
                     │ Gemini 3.8 Flash Agent │   │   Google Cloud OLAP │
                     │ (Structured Ingestion, │   │ BigQuery Streaming  │
                     │  Barcode Normalization,│   │ & Firestore Metadata│
                     │  Store Fuzzy Matching) │   │                     │
                     └────────────────────────┘   └─────────────────────┘
```

## Directory Structure
- [`backend-go/`](file:///Users/fathalla/Development/Tashil%20Data%20Sharing/backend-go/): Cloud Run backend service in Go.
  - `cmd/server/main.go`: Server entrypoint with graceful shutdown.
  - `internal/service/gemini/`: Gemini 3.8 Flash AI ingestion agent with structured JSON outputs.
  - `internal/service/bigquery/`: BigQuery streaming OLAP client with RLS.
  - `internal/service/firestore/`: Firestore sync client for tenants, stores, and OOS alerts.
  - `internal/middleware/`: JWT verification and tenant Row-Level Security (RLS).
  - `Dockerfile`: Multi-stage scratch container build.
- [`tashil_web/`](file:///Users/fathalla/Development/Tashil%20Data%20Sharing/tashil_web/): Flutter Desktop-First Web Portal.
  - `lib/core/theme/`: Material Design 3 (`ColorScheme.fromSeed`, Surface Container Tiers, Cairo font, 8dp Spacing Grid).
  - `lib/core/layout/`: 5 Window Size Classes, Max-Width Containment (1440dp), 3-Tier Adaptive Navigation.
  - `lib/features/executive_dashboard/`: Executive Bento KPI Grid, Daily Sell-Out Trend Canvas Chart, Chain Market Share.
  - `lib/features/data_ingestion/`: Excel/CSV Drag & Drop, Gemini AI Ingestion Progress, Anomaly Resolution Table.
  - `lib/features/sell_out_analytics/`: Cascading Filter Toolbar, Virtualized DataGrid with Pinned Columns, Excel Export.
  - `lib/features/oos_monitor/`: Out-of-Stock Alert Monitor with estimated daily lost revenue.

## Running the Platform

### Backend Service (Go)
```bash
cd backend-go
go run cmd/server/main.go
# Server listens on http://localhost:8080
```

### Frontend Portal (Flutter Web)
```bash
cd tashil_web
flutter run -d chrome
# Launches web portal with Arabic RTL and M3 design
```

## Cursor cloud agents

Cloud agents use [`.cursor/environment.json`](.cursor/environment.json). The image pins Flutter 3.41.2 (web precached, analytics off) and Go 1.26.0; [`.cursor/install.sh`](.cursor/install.sh) only syncs pub, Go modules, and the Playwright npm cache. Versions, verification commands, and the dashboard step for the saved `Tashil-Data-Sharing` environment are in [`.cursor/README.md`](.cursor/README.md).
