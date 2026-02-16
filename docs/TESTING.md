# Testing Guide

This guide covers how to test the NYC Taxi Data Pipeline.

## Quick Test Commands

### 1. Test Data Ingestion

```bash
# Create a small test CSV
cat > data/raw/test_small.csv << 'EOF'
id,vendor_id,pickup_datetime,dropoff_datetime,passenger_count,pickup_longitude,pickup_latitude,dropoff_longitude,dropoff_latitude,store_and_fwd_flag,trip_duration
id001,2,2016-03-14 17:24:55,2016-03-14 17:32:30,1,-73.982155,40.767937,-73.964630,40.765602,N,455
id002,1,2016-06-12 00:43:35,2016-06-12 00:54:38,1,-73.980415,40.738564,-73.999481,40.731152,N,663
id003,2,2016-01-19 11:35:24,2016-01-19 12:10:48,1,-73.979027,40.763939,-74.005333,40.710087,N,2124
EOF

# Run ingestion on test file
docker-compose exec ingestion-service \
  python ingestion_service.py /app/data/raw/test_small.csv
```

### 2. Test Database Connection

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U taxiuser -d nyc_taxi

# Run test queries
SELECT COUNT(*) FROM raw.trip_data;
SELECT * FROM raw.trip_data LIMIT 5;
\q
```

### 3. Test MinIO Upload

```bash
# Access MinIO console
# Open http://localhost:9001
# Login: minioadmin / minioadmin
# Check raw-data bucket for uploaded files
```

### 4. Test Spark Processing

```bash
# Run processing on test data
docker-compose exec spark-master \
  spark-submit \
  --master local[*] \
  --packages org.postgresql:postgresql:42.6.0 \
  /opt/spark-apps/processing_service.py

# Check results
docker-compose exec postgres psql -U taxiuser -d nyc_taxi -c \
  "SELECT COUNT(*) FROM processed.trip_features;"
```

### 5. Test API Endpoints

```bash
# Health check
curl http://localhost:8000/health

# Get stats (replace API key)
curl -H "X-API-Key: your-secret-api-key" \
  http://localhost:8000/stats

# Get trips
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?limit=5" | jq

# Test pagination
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?limit=10&offset=10" | jq

# Test filtering
curl -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?vendor_id=2&min_quality=0.9" | jq
```

### 6. Test Airflow DAGs

```bash
# List DAGs
docker-compose exec airflow-scheduler \
  airflow dags list

# Test DAG (dry run)
docker-compose exec airflow-scheduler \
  airflow dags test monthly_ingestion 2024-01-01

# Trigger DAG
docker-compose exec airflow-scheduler \
  airflow dags trigger monthly_ingestion

# Check DAG status
docker-compose exec airflow-scheduler \
  airflow dags list-runs -d monthly_ingestion
```

## Integration Tests

### End-to-End Test

```bash
#!/bin/bash
# test_e2e.sh

echo "Starting E2E test..."

# 1. Create test data
echo "Creating test data..."
cat > data/raw/test_e2e.csv << 'EOF'
id,vendor_id,pickup_datetime,dropoff_datetime,passenger_count,pickup_longitude,pickup_latitude,dropoff_longitude,dropoff_latitude,store_and_fwd_flag,trip_duration
test001,2,2016-03-14 17:24:55,2016-03-14 17:32:30,1,-73.982155,40.767937,-73.964630,40.765602,N,455
test002,1,2016-06-12 00:43:35,2016-06-12 00:54:38,1,-73.980415,40.738564,-73.999481,40.731152,N,663
EOF

# 2. Run ingestion
echo "Running ingestion..."
docker-compose exec -T ingestion-service \
  python ingestion_service.py /app/data/raw/test_e2e.csv

# 3. Verify ingestion
echo "Verifying ingestion..."
COUNT=$(docker-compose exec -T postgres psql -U taxiuser -d nyc_taxi -t -c \
  "SELECT COUNT(*) FROM raw.trip_data WHERE id LIKE 'test%';")

if [ "$COUNT" -eq 2 ]; then
  echo "✓ Ingestion successful: $COUNT records"
else
  echo "✗ Ingestion failed: expected 2, got $COUNT"
  exit 1
fi

# 4. Run processing
echo "Running processing..."
docker-compose exec -T spark-master \
  spark-submit \
  --master local[*] \
  --packages org.postgresql:postgresql:42.6.0 \
  /opt/spark-apps/processing_service.py

# 5. Verify processing
echo "Verifying processing..."
PROC_COUNT=$(docker-compose exec -T postgres psql -U taxiuser -d nyc_taxi -t -c \
  "SELECT COUNT(*) FROM processed.trip_features WHERE trip_id LIKE 'test%';")

if [ "$PROC_COUNT" -eq 2 ]; then
  echo "✓ Processing successful: $PROC_COUNT records"
else
  echo "✗ Processing failed: expected 2, got $PROC_COUNT"
  exit 1
fi

# 6. Test API
echo "Testing API..."
RESPONSE=$(curl -s -H "X-API-Key: your-secret-api-key" \
  "http://localhost:8000/trips?limit=1")

if echo "$RESPONSE" | grep -q "trip_id"; then
  echo "✓ API test successful"
else
  echo "✗ API test failed"
  exit 1
fi

echo "E2E test completed successfully!"
```

Save as `scripts/test_e2e.sh`, then run:
```bash
chmod +x scripts/test_e2e.sh
./scripts/test_e2e.sh
```

## Performance Tests

### Load Test API

```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Test API performance (100 requests, 10 concurrent)
ab -n 100 -c 10 \
  -H "X-API-Key: your-secret-api-key" \
  http://localhost:8000/trips?limit=10

# Expected: < 100ms per request
```

### Ingestion Performance

```bash
# Test with full dataset
time docker-compose exec ingestion-service \
  python ingestion_service.py /app/data/raw/train.csv

# Expected time: 5-15 minutes (depends on machine)
```

### Processing Performance

```bash
# Time Spark processing
time docker-compose exec spark-master \
  spark-submit \
  --master spark://spark-master:7077 \
  --packages org.postgresql:postgresql:42.6.0 \
  /opt/spark-apps/processing_service.py

# Expected time: 10-30 minutes (depends on machine and data size)
```

## Data Quality Tests

### Validation Tests

```sql
-- Connect to database
docker-compose exec postgres psql -U taxiuser -d nyc_taxi

-- Test 1: No null IDs
SELECT COUNT(*) FROM raw.trip_data WHERE id IS NULL;
-- Expected: 0

-- Test 2: Valid coordinates (NYC area)
SELECT COUNT(*) FROM raw.trip_data 
WHERE pickup_latitude NOT BETWEEN 40.5 AND 41.0
   OR pickup_longitude NOT BETWEEN -74.3 AND -73.7;
-- Expected: 0 (all invalid should be filtered)

-- Test 3: Positive trip duration
SELECT COUNT(*) FROM raw.trip_data WHERE trip_duration <= 0;
-- Expected: 0

-- Test 4: Valid passenger count
SELECT COUNT(*) FROM raw.trip_data 
WHERE passenger_count <= 0 OR passenger_count > 9;
-- Expected: 0

-- Test 5: Feature engineering correctness
SELECT 
  trip_id,
  pickup_datetime,
  pickup_hour,
  EXTRACT(HOUR FROM pickup_datetime) as expected_hour
FROM processed.trip_features
WHERE pickup_hour != EXTRACT(HOUR FROM pickup_datetime)
LIMIT 5;
-- Expected: 0 rows (all hours should match)

-- Test 6: Distance calculation
SELECT 
  trip_id,
  distance_km,
  avg_speed_kmh
FROM processed.trip_features
WHERE distance_km <= 0 OR avg_speed_kmh <= 0
LIMIT 10;
-- Expected: 0 rows or very few (outliers only)

-- Test 7: Aggregation accuracy
SELECT 
  date_hour,
  total_trips,
  avg_trip_duration
FROM aggregated.hourly_stats
WHERE total_trips = 0 OR avg_trip_duration IS NULL
LIMIT 5;
-- Expected: 0 rows
```

## Unit Tests (Python)

Create `tests/test_ingestion.py`:

```python
import unittest
import pandas as pd
import sys
sys.path.append('microservices/ingestion')
from ingestion_service import DataIngestionService

class TestIngestionService(unittest.TestCase):
    
    def setUp(self):
        self.service = DataIngestionService()
    
    def test_validate_data_removes_duplicates(self):
        # Create test data with duplicates
        df = pd.DataFrame({
            'id': ['1', '1', '2'],
            'vendor_id': [1, 1, 2],
            'pickup_datetime': ['2016-01-01'] * 3,
            'dropoff_datetime': ['2016-01-01'] * 3,
            'passenger_count': [1, 1, 1],
            'pickup_longitude': [-73.98] * 3,
            'pickup_latitude': [40.76] * 3,
            'dropoff_longitude': [-73.96] * 3,
            'dropoff_latitude': [40.77] * 3,
            'trip_duration': [600] * 3,
        })
        
        validated_df, stats = self.service.validate_data(df)
        
        self.assertEqual(len(validated_df), 2)
        self.assertEqual(stats['checks'][0]['removed'], 1)
    
    def test_validate_data_removes_invalid_coords(self):
        # Create test data with invalid coordinates
        df = pd.DataFrame({
            'id': ['1', '2'],
            'vendor_id': [1, 1],
            'pickup_datetime': ['2016-01-01'] * 2,
            'dropoff_datetime': ['2016-01-01'] * 2,
            'passenger_count': [1, 1],
            'pickup_longitude': [-73.98, -80.0],  # Second is invalid
            'pickup_latitude': [40.76, 40.76],
            'dropoff_longitude': [-73.96, -73.96],
            'dropoff_latitude': [40.77, 40.77],
            'trip_duration': [600, 600],
        })
        
        validated_df, stats = self.service.validate_data(df)
        
        self.assertEqual(len(validated_df), 1)

if __name__ == '__main__':
    unittest.main()
```

Run tests:
```bash
docker-compose exec ingestion-service python -m pytest tests/
```

## Monitoring Tests

### Check Service Health

```bash
# Check all containers are running
docker-compose ps

# Check container health
docker-compose ps | grep "healthy"

# Check logs for errors
docker-compose logs --tail=100 | grep -i error
```

### Database Health

```bash
# Connection test
docker-compose exec postgres pg_isready -U taxiuser

# Database size
docker-compose exec postgres psql -U taxiuser -d nyc_taxi -c \
  "SELECT pg_size_pretty(pg_database_size('nyc_taxi'));"

# Table sizes
docker-compose exec postgres psql -U taxiuser -d nyc_taxi -c "
  SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
  FROM pg_tables
  WHERE schemaname IN ('raw', 'processed', 'aggregated')
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

## Troubleshooting Tests

If tests fail, check:

1. **All services running**: `docker-compose ps`
2. **Logs for errors**: `docker-compose logs [service-name]`
3. **Database connection**: Can you connect to PostgreSQL?
4. **Data file exists**: Is `train.csv` in `data/raw/`?
5. **Network connectivity**: Can services reach each other?
6. **Disk space**: `docker system df`
7. **Memory**: `docker stats`

## Test Data Cleanup

```bash
# Clean test data from database
docker-compose exec postgres psql -U taxiuser -d nyc_taxi << EOF
DELETE FROM raw.trip_data WHERE id LIKE 'test%';
DELETE FROM processed.trip_features WHERE trip_id LIKE 'test%';
EOF

# Remove test files
rm data/raw/test_*.csv
```

## Continuous Testing

For CI/CD integration, create `.github/workflows/test.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Start services
      run: docker-compose up -d
    
    - name: Wait for services
      run: sleep 60
    
    - name: Run E2E tests
      run: ./scripts/test_e2e.sh
    
    - name: Stop services
      run: docker-compose down -v
```
