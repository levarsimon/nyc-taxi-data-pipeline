# NYC Taxi Data Pipeline - Setup Guide

### System Requirements
- **OS**: Linux, macOS, or Windows with Windows Subsystem for Linux 2
- **RAM**: Minimum 8GB (16GB recommended)
- **Storage**: 10GB free space
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher

### Software Installation

#### 1. Install Docker
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker.io docker-compose

# macOS
brew install docker docker-compose

# Windows
Docker Desktop requires Windows Subsystem for Linux 2 (WSL2)
wsl --install
Download Docker Desktop installer from https://www.docker.com/products/docker-desktop/
Run the installer

# Verify installation
docker --version
docker-compose --version
```

#### 2. Clone Repository
```bash
git clone https://github.com/levarsimon/nyc-taxi-data-pipeline.git
cd nyc-taxi-data-pipeline
```

### Download NYC Taxi Dataset

1. Go to Kaggle: https://www.kaggle.com/datasets/yasserh/nyc-taxi-trip-duration
2. Download `NYC.csv.zip` (1.4M+ records, ~200MB)
3. Extract `NYC.csv` from the zip file
4. Rename `NYC.csv`  to `train.csv`
5. Place `train.csv` in data/raw/


## Project Setup

### Step 1: Configure Environment Variables

The `.env` file is already configured with defaults. For production, update:

```bash
# Edit .env file
nano .env

# Update these values for production:
POSTGRES_PASSWORD=<strong-password>
MINIO_ROOT_PASSWORD=<strong-password>
API_KEY=<the-secure-api-key>
```

### Step 2: Build and Start Services

```bash
# Start all services
docker-compose up -d

# This will start:
# - PostgreSQL (port 5432)
# - MinIO (ports 9000, 9001)
# - Spark Master (port 8081)
# - Spark Worker
# - Airflow Scheduler
# - Airflow Webserver (port 8080)
# - Data Delivery API (port 8000)
```

### Step 3: Wait for Services to Initialize

```bash
# Check service status
docker-compose ps

# All services should show "Up" status
# Wait ~2 minutes for full initialization

# Check logs if issues occur
docker-compose logs -f airflow-webserver
```

### Step 4: Access Web Interfaces

1. **Airflow UI**
   - URL: http://localhost:8080
   - Username: `admin`
   - Password: `admin`

2. **MinIO Console**
   - URL: http://localhost:9001
   - Username: `minioadmin`
   - Password: `minioadmin`

3. **Spark Master UI**
   - URL: http://localhost:8081

4. **Data API**
   - URL: http://localhost:8000
   - API Docs: http://localhost:8000/docs

## Running the Pipeline

1. Open Airflow UI: http://localhost:8080
2. Enable DAGs:
   - Toggle `monthly_ingestion` to ON
   - Toggle `quarterly_processing` to ON
3. Trigger monthly ingestion (one of the options):
   a. Manually:
      - Click on `monthly_ingestion`
      - Click "Trigger DAG" (play button)
      - Wait for completion (~5-10 minutes depending on your machine)
   b. Using Airflow CLI:
      ```bash
      docker-compose exec airflow-scheduler airflow dags trigger monthly_ingestion
      ```
   c. Run ingestion directly:
      ```bash
      docker-compose exec ingestion-service python ingestion_service.py /app/data/raw/train.csv
      ```
4. After ingestion completes, trigger processing:
   ```bash
   script/run_spark_processing.bat
   ```

# Check DAG status
```bash
docker-compose exec airflow-scheduler airflow dags list-runs -d monthly_ingestion
```

## Verification

### 1. Check Database

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U taxiuser -d nyc_taxi

# Check data counts
SELECT COUNT(*) FROM raw.trip_data;
SELECT COUNT(*) FROM processed.trip_features;
SELECT COUNT(*) FROM aggregated.hourly_stats;
SELECT COUNT(*) FROM aggregated.daily_stats;

# Exit
\q
```

### 2. Check MinIO Storage

1. Open MinIO Console: http://localhost:9001
2. Login with credentials
3. Navigate to `raw-data` bucket
4. You should see uploaded CSV file

### 3. Test API

```bash
# Health check
curl http://localhost:8000/health

# Get statistics (requires API key)
curl -H "X-API-Key: the-secret-api-key" http://localhost:8000/stats

# Get sample trips
curl -H "X-API-Key: the-secret-api-key" "http://localhost:8000/trips?limit=10"

# Get hourly aggregations
curl -H "X-API-Key: the-secret-api-key" "http://localhost:8000/aggregated/hourly?limit=10"
```

### 4. API Interactive Documentation

Open http://localhost:8000/docs for interactive Swagger UI:
- Test all endpoints
- View request/response schemas
- Generate sample requests

## Monitoring

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f airflow-scheduler
docker-compose logs -f spark-master
docker-compose logs -f delivery-api

# Follow logs from specific time
docker-compose logs --since 30m -f
```


## Troubleshooting

### Issue: Services won't start

```bash
# Stop all services
docker-compose down

# Remove volumes (deletes all data)
docker-compose down -v

# Rebuild and start
docker-compose up -d --build
```

## Stopping the Pipeline

### Graceful Shutdown
```bash
# Stop all services
docker-compose down

# Stop and remove volumes (deletes all data)
docker-compose down -v
```

### Keep Data, Stop Services
```bash
# Stop containers but keep data
docker-compose stop
```

## Data Cleanup

### Clear Processed Data (keep raw)
```bash
docker-compose exec postgres psql -U taxiuser -d nyc_taxi -c "
  TRUNCATE processed.trip_features CASCADE;
  TRUNCATE aggregated.hourly_stats CASCADE;
  TRUNCATE aggregated.daily_stats CASCADE;
"
```

### Complete Reset
```bash
# Stop and remove everything
docker-compose down -v

# Remove data directory (optional)
rm -rf data/processed/*

# Restart
docker-compose up -d
```

## Common Commands Reference

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f [service_name]

# Restart service
docker-compose restart [service_name]

# Execute command in container
docker-compose exec [service_name] [command]

# Rebuild services
docker-compose up -d --build

# Check service status
docker-compose ps

# View resource usage
docker stats
```
