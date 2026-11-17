# Tashil Data Sharing - Flutter Web Desktop Portal

Desktop-first Material Design 3 (M3) executive web portal built for FMCG and retail leaders (Adeco, Unilever, PepsiCo) to monitor real-time sell-out performance, out-of-stock incidents, and AI-driven data ingestion.

## Design System & M3 Standards
- **Google Material Design 3 (M3)**: Full `useMaterial3: true` adherence with single seed dynamic color derivation (`ColorScheme.fromSeed`).
- **Multi-Tenant Branding**: Dynamic seed switching between Adeco (`#35A211` ADCO logo green), Unilever (`#0D9488`), and PepsiCo (`#B91C1C`).
- **Surface Container Tiers**: Explicit application of `surfaceContainerLow` (cards), `surfaceContainer` (sidebar), `surfaceContainerHigh` (dialogs/elevated metrics), and `surfaceContainerHighest` (inputs).
- **Arabic RTL-First**: Native right-to-left layout directionality with Google Fonts **Cairo** (`GoogleFonts.cairoTextTheme`).
- **M3 Window Size Classes**: Responsive breakpoints (<600dp Compact, 600-839dp Medium, 840-1199dp Expanded, 1200-1599dp Large, ≥1600dp Extra Large).
- **Max-Width Containment**: Bounded to `1440dp` with symmetric breathing margins via `M3ContentBoundary`.
- **8dp Baseline Spacing**: Enforced through `M3Spacing` scale (4, 8, 16, 24, 32, 40, 48, 64).
- **Connected Button Groups**: Segmented buttons with `StadiumBorder` for date and filter selection.
- **Strict Single-Icon Rule**: Buttons use at most one clean M3 icon without mixing emojis into text labels.

## Core Screens
1. **Executive Dashboard (`ExecutiveScreen`)**:
   - Bento Grid KPI cards (Total Sell-Out Revenue, Volume, Active Outlets, OOS Rate %).
   - Daily Sell-Out Growth Trend Canvas Chart with hover tooltips.
   - Retail Chain Market Share Distribution (Carrefour, Fathalla, Gomla Market, Spinneys).
2. **Sell-Out Explorer (`SellOutExplorerScreen`)**:
   - Cascading filter bar (Chain -> Store, Category -> SKU, Search).
   - High-density virtualized data grid with sticky columns.
   - One-click Excel / CSV export with Arabic UTF-8 BOM.
3. **AI Ingestion Portal (`UploadPortalScreen`)**:
   - Drag & drop / file selector for Excel (.xlsx, .xls) and CSV.
   - Quick one-click testing templates (Carrefour, Fathalla, Gomla).
   - Gemini 3.8 Flash AI ingestion progress and structured extraction breakdown.
   - Semantic anomaly resolution table.
4. **Out-of-Stock Monitor (`OOSDashboardScreen`)**:
   - Real-time zero-sales anomaly alerting with estimated daily lost revenue in EGP.

## Deploying the web app

Run `scripts/deploy_web.sh` from the repo root. It bumps `tashil_web/deploy_version.txt`,
builds with `--dart-define=APP_VERSION=<n>`, deploys to Firebase Hosting
(`tashil-data-sharing`), and commits the version file as `chore: web deploy vN` (no push).
On failure the previous number is restored. The version appears in the sidebar
footer (`Tashil • Data Sharing Platform • v3`); local runs without the define show `dev`.
Counter started at 1 on 2026-10-24 (earlier manual deploys were not counted).
