# Tashil Data Sharing - Go Cloud Run Backend

High-throughput, low-latency multi-tenant backend service designed for Google Cloud Run, integrating Gemini 3.8 Flash AI ingestion, BigQuery streaming, and Firestore synchronization with strict Row-Level Security (RLS).

## Key Features
- **Gemini 3.8 Flash AI Agent**: Ingests unstructured/differing retail sales files (Carrefour, Fathalla, Gomla Market, Spinneys), performs column mapping, GTIN barcode normalization, store entity fuzzy resolution, and anomaly detection.
- **Near-Zero Cold Start**: Built with lightweight Go 1.22 compiled binaries (<25MB image size, boots in <50ms on Cloud Run).
- **Google BigQuery Integration**: Batch streaming of sell-out transaction facts with multi-tenant row partitioning.
- **Row-Level Security (RLS)**: Enforces tenant isolation (`tenant_id`) across all OLAP queries, mutations, and metadata lookups.
- **Full Fallback / Mock Engine**: Provides instant zero-setup local development experience while mirroring GCP production behavior.

## API Endpoints

| Method | Path | Description | Protected |
| :--- | :--- | :--- | :--- |
| `GET` | `/healthz` | Container health probe | No |
| `POST` | `/api/v1/ingest/upload` | Upload Excel/CSV file for AI ingestion | Yes (JWT) |
| `GET` | `/api/v1/analytics/executive-summary` | Bento Grid KPIs, chain shares, trend points | Yes (JWT) |
| `GET` | `/api/v1/analytics/records` | Paginated virtualized table records | Yes (JWT) |
| `GET` | `/api/v1/analytics/oos-monitor` | Out-of-Stock alert monitor | Yes (JWT) |
| `GET` | `/api/v1/stores` | Store catalog for tenant | Yes (JWT) |
| `GET` | `/api/v1/tenants` | List available enterprise tenants | Yes (JWT) |
| `GET` | `/api/v1/batches` | Recent ingestion batches | Yes (JWT) |

## Environment Variables
- `PORT`: HTTP port (default: `8080`)
- `PROJECT_ID`: Google Cloud Project ID
- `BIGQUERY_DATASET`: Dataset name (default: `tashil_analytics`)
- `GEMINI_API_KEY`: API key for Gemini 3.8 Flash
- `GEMINI_MODEL`: Model name (default: `gemini-3.8-flash`)
- `JWT_SECRET`: Secret key for HMAC-SHA256 signature verification
- `USE_MOCK_SERVICES`: Force mock services for local execution (`true`/`false`)
