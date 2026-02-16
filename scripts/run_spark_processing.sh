#!/bin/bash
# Run Spark Processing Manually
# Use this script to process the ingested data with Apache Spark

echo "=========================================="
echo "NYC Taxi Data - Spark Processing"
echo "=========================================="
echo ""

# Check if Spark master is running
if ! docker ps | grep -q nyc-taxi-spark-master; then
    echo "ERROR: Spark master is not running"
    echo "Start it with: docker-compose up -d spark-master"
    exit 1
fi

echo "Submitting Spark job to cluster..."
echo ""

# Run spark-submit in the Spark master container
docker exec nyc-taxi-spark-master \
  /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --executor-memory 2g \
  --driver-memory 1g \
  --packages org.postgresql:postgresql:42.6.0 \
  /opt/spark-apps/processing_service.py

EXIT_CODE=$?

echo ""
echo "=========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Spark processing completed successfully!"
    echo ""
    echo "Verify the results:"
    echo "  docker-compose exec postgres psql -U taxiuser -d nyc_taxi"
    echo "  SELECT COUNT(*) FROM processed.trip_features;"
    echo "  SELECT COUNT(*) FROM aggregated.hourly_stats;"
    echo "  SELECT COUNT(*) FROM aggregated.daily_stats;"
else
    echo "✗ Spark processing failed with exit code: $EXIT_CODE"
    echo ""
    echo "Check logs with:"
    echo "  docker-compose logs spark-master"
    exit $EXIT_CODE
fi

echo "=========================================="