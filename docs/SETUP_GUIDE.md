# NYC Taxi Data Pipeline - Setup Guide

## Prerequisites

### System Requirements
- **OS**: Linux, macOS, or Windows with WSL2
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

# Verify installation
docker --version
docker-compose --version
```

#### 2. Clone Repository
```bash
git clone <your-repository-url>
cd nyc-taxi-data-pipeline
```

## Data Preparation

### Download NYC Taxi Dataset

1. Go to Kaggle: https://www.kaggle.com/c/nyc-taxi-trip-duration/data
2. Download `train.csv` (1.4M+ records, ~200MB)
3. Place the file in the project:
   ```bash
   mkdir -p data/raw
   mv ~/Downloads/train.csv data/raw/
   ```

### Verify Data
```bash
# Check file exists
ls -lh data/raw/train.csv

# Quick preview (first 5 rows)
head -n 5 data/raw/train.csv
```

## Project Setup

### Step 1: Configure Environment Variables

The `.env` file is already configured with defaults. For production, update:

```bash
# Edit .env file
nano .env

# Update these values for production:
POSTGRES_PASSWORD=<strong-password>
MINIO_ROOT_PASSWORD=<strong-password>
API_KEY=<your-secure-api-key>
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

### Method 1: Using Airflow UI (Recommended)

1. Open Airflow UI: http://localhost:8080
2. Enable DAGs:
   - Toggle `monthly_ingestion` to ON
   - Toggle `quarterly_processing` to ON
3. Trigger manually:
   - Click on `monthly_ingestion`
   - Click "Trigger DAG" (play button)
   - Wait for completion (~5-10 minutes depending on your machine)
4. After ingestion completes, trigger processing:
   - Click on `quarterly_processing`
   - Click "Trigger DAG"
   - Wait for completion (~10-20 minutes)

### Method 2: Using Airflow CLI

```bash
# Trigger monthly ingestion
docker-compose exec airflow-scheduler \
  airflow dags trigger monthly_ingestion

# Wait for completion, then trigger processing
docker-compose exec airflow-scheduler \
  airflow dags trigger quarterly_processing

# Check DAG status
docker-compose exec airflow-scheduler \
  airflow dags list-runs -d monthly_ingestion
```

### Method 3: Direct Execution (Development/Testing)

```bash
# Run ingestion directly
docker-compose exec ingestion-service \
  python ingestion_service.py /app/data/raw/train.csv

# Run processing directly
docker-compose exec spark-master \
  spark-submit \
  --master spark://spark-master:7077 \
  --packages org.postgresql:postgresql:42.6.0 \
  /opt/spark-apps/processing_service.py
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
4. You should see uploaded CSV files

### 3. Test API

```bash
# Health check
curl http://localhost:8000/health

# Get statistics (requires API key)
curl -H "X-API-Key: your-secret-api-key" \
  http://localhost:8000/stats

# Get sample trips
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?limit=10"

# Get hourly aggregations
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/aggregated/hourly?limit=10"
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

### Check Resource Usage

```bash
# Container stats
docker stats

# Disk usage
docker system df
```

## Troubleshooting

### Issue: Services won't start

```bash
# Stop all services
docker-compose down

# Remove volumes (WARNING: deletes all data)
docker-compose down -v

# Rebuild and start
docker-compose up -d --build
```

### Issue: Out of memory

```bash
# Adjust Docker memory limits
# Edit docker-compose.yml, add to services:
#   mem_limit: 2g
#   memswap_limit: 2g

# Or increase Docker Desktop memory allocation
```

### Issue: Port conflicts

```bash
# Check which process uses port
lsof -i :8080  # for Airflow
lsof -i :5432  # for PostgreSQL

# Kill process or change port in docker-compose.yml
```

### Issue: Airflow DAGs not appearing

```bash
# Restart Airflow scheduler
docker-compose restart airflow-scheduler

# Check DAG folder permissions
ls -la airflow/dags/

# Verify DAG syntax
docker-compose exec airflow-scheduler \
  python -m py_compile /opt/airflow/dags/monthly_ingestion_dag.py
```

### Issue: Spark job fails

```bash
# Check Spark logs
docker-compose logs spark-master
docker-compose logs spark-worker

# Verify PostgreSQL JDBC driver
docker-compose exec spark-master \
  ls -la /opt/spark/jars/postgresql*.jar

# If missing, download it:
docker-compose exec spark-master bash
cd /opt/spark/jars
wget https://jdbc.postgresql.org/download/postgresql-42.6.0.jar
exit
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

## Next Steps

1. **Customize Processing**: Edit `processing_service.py` to add custom features
2. **Adjust Scheduling**: Modify DAG schedules in `airflow/dags/`
3. **Add Monitoring**: Integrate Prometheus/Grafana
4. **Deploy to Cloud**: Adapt for AWS/Azure/GCP
5. **Add ML Models**: Connect your ML training pipeline to the API

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

## Getting Help

- Check logs: `docker-compose logs -f`
- Airflow UI: http://localhost:8080
- API Docs: http://localhost:8000/docs
- GitHub Issues: <your-repo-url>/issues

## Production Deployment

For production deployment:
1. Use strong passwords in `.env`
2. Enable HTTPS/SSL
3. Set up proper backups
4. Configure monitoring and alerting
5. Use secrets management (e.g., HashiCorp Vault)
6. Deploy to Kubernetes or cloud services
7. Set up CI/CD pipeline
8. Configure autoscaling
9. Enable audit logging
10. Implement disaster recovery plan
