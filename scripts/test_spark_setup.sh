#!/bin/bash
# Test Spark Setup

echo "=========================================="
echo "Testing Spark Setup"
echo "=========================================="
echo ""

echo "1. Checking if Spark master is running..."
if docker ps | grep -q nyc-taxi-spark-master; then
    echo "   ✓ Spark master is running"
else
    echo "   ✗ Spark master is NOT running"
    echo "   Start it with: docker-compose up -d spark-master"
    exit 1
fi

echo ""
echo "2. Checking if Spark worker is connected..."
if docker ps | grep -q nyc-taxi-spark-worker; then
    echo "   ✓ Spark worker is running"
else
    echo "   ✗ Spark worker is NOT running"
    echo "   Start it with: docker-compose up -d spark-worker"
    exit 1
fi

echo ""
echo "3. Checking if processing script exists..."
if docker exec nyc-taxi-spark-master test -f /opt/spark-apps/processing_service.py; then
    echo "   ✓ Processing script found"
else
    echo "   ✗ Processing script NOT found"
    echo "   Check volume mount in docker-compose.yml"
    exit 1
fi

echo ""
echo "4. Testing simple Spark job..."
docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit \
    --master local[1] \
    --deploy-mode client \
    --class org.apache.spark.examples.SparkPi \
    /opt/spark/examples/jars/spark-examples_*.jar \
    10

if [ $? -eq 0 ]; then
    echo "   ✓ Simple Spark job succeeded"
else
    echo "   ✗ Simple Spark job failed"
    exit 1
fi

echo ""
echo "5. Checking PostgreSQL connectivity..."
docker exec postgres psql -U taxiuser -d nyc_taxi -c "SELECT 1;" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "   ✓ Can connect to PostgreSQL"
else
    echo "   ✗ Cannot connect to PostgreSQL"
    echo "   Make sure PostgreSQL is running"
    exit 1
fi

echo ""
echo "6. Checking data in database..."
COUNT=$(docker exec postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2>/dev/null | tr -d '[:space:]')
if [ "$COUNT" -gt 0 ] 2>/dev/null; then
    echo "   ✓ Found $COUNT records in raw.trip_data"
else
    echo "   ✗ No data found in raw.trip_data"
    echo "   Run monthly ingestion first"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ All checks passed!"
echo "=========================================="
echo ""
echo "Ready to run Spark processing."
echo ""
echo "Run: ./scripts/run_spark_processing.sh"
echo ""