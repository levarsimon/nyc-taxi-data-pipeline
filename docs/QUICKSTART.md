# Quick Start Guide - NYC Taxi Data Pipeline

Get the system running in 10 minutes!

## Prerequisites

- Docker & Docker Compose installed
- 8GB+ RAM available
- 10GB+ disk space
- NYC Taxi dataset downloaded

## Step 1: Download Dataset (5 min)

1. Visit: https://www.kaggle.com/c/nyc-taxi-trip-duration/data
2. Download `train.csv` (~200MB)
3. Place in `data/raw/` directory

```bash
# Create directory if it doesn't exist
mkdir -p data/raw

# Move downloaded file
mv ~/Downloads/train.csv data/raw/
```

## Step 2: Start System (2 min)

```bash
# Navigate to project directory
cd nyc-taxi-data-pipeline

# Start all services
docker-compose up -d

# Wait for initialization (view logs)
docker-compose logs -f
```

**Wait for**: "Airflow webserver is ready" message

## Step 3: Run Pipeline (3 min)

### Option A: Using Airflow UI (Recommended)

1. Open browser: http://localhost:8080
2. Login: `admin` / `admin`
3. Click on `monthly_ingestion` DAG
4. Click "Trigger DAG" button (▶️)
5. Wait ~5-10 minutes
6. Once complete, trigger `quarterly_processing` DAG
7. Wait ~10-20 minutes

### Option B: Using Command Line

```bash
# Trigger ingestion
docker-compose exec airflow-scheduler \
  airflow dags trigger monthly_ingestion

# Wait for completion (~10 min), then trigger processing
docker-compose exec airflow-scheduler \
  airflow dags trigger quarterly_processing
```

## Step 4: Access Data

### Via API

```bash
# Check system health
curl http://localhost:8000/health

# Get statistics
curl -H "X-API-Key: your-secret-api-key" \
  http://localhost:8000/stats

# Get sample trips
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?limit=5" | jq
```

### Via API Documentation

Open: http://localhost:8000/docs

Interactive Swagger UI with all endpoints!

### Via Database

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U taxiuser -d nyc_taxi

# Query data
SELECT COUNT(*) FROM raw.trip_data;
SELECT COUNT(*) FROM processed.trip_features;
SELECT * FROM aggregated.hourly_stats LIMIT 5;
```

## All Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Airflow UI | http://localhost:8080 | admin / admin |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Spark Master UI | http://localhost:8081 | - |
| Data API | http://localhost:8000 | API Key: your-secret-api-key |
| API Docs | http://localhost:8000/docs | - |

## Verification Checklist

- [ ] All containers running: `docker-compose ps`
- [ ] Airflow UI accessible
- [ ] Data ingested: Check `/stats` endpoint
- [ ] Data processed: Check PostgreSQL
- [ ] API responding: Test `/health` endpoint

## Common Commands

```bash
# View logs
docker-compose logs -f [service_name]

# Stop system
docker-compose down

# Restart service
docker-compose restart [service_name]

# Check status
docker-compose ps

# View resource usage
docker stats
```

## Troubleshooting

### Services won't start
```bash
docker-compose down -v
docker-compose up -d --build
```

### Out of memory
- Increase Docker memory limit (Docker Desktop settings)
- Or reduce Spark worker memory in `docker-compose.yml`

### Port conflicts
- Change ports in `docker-compose.yml`
- Or stop conflicting services

### Can't see DAGs in Airflow
```bash
# Restart scheduler
docker-compose restart airflow-scheduler

# Check DAG folder
ls -la airflow/dags/
```

## What's Running?

After `docker-compose up -d`:

1. **PostgreSQL** - Stores all data (raw, processed, aggregated)
2. **MinIO** - Stores raw CSV files (S3-compatible)
3. **Spark Master + Worker** - Processes data
4. **Airflow Scheduler + Webserver** - Orchestrates workflows
5. **Ingestion Service** - Ingests CSV data
6. **Delivery API** - Provides REST API

## Next Steps

1. ✅ Explore Airflow UI to understand workflows
2. ✅ Try API endpoints in Swagger docs
3. ✅ Query database to see data transformations
4. ✅ Review architecture diagram in `docs/ARCHITECTURE.md`
5. ✅ Customize processing logic for your use case
6. ✅ Add this to your portfolio!

## Need More Help?

- Full setup: See `SETUP_GUIDE.md`
- Testing: See `TESTING.md`
- Architecture: See `docs/ARCHITECTURE.md`
- Issues: Check `docker-compose logs`

## System Overview

```
Data Flow:
CSV → Ingestion → MinIO + PostgreSQL → 
Spark Processing → Aggregations → API → Your ML App
```

Happy data engineering! 🚀
