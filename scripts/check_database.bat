@echo off
echo ==========================================
echo Database Status Check
echo ==========================================
echo.

echo Checking raw data table...
docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT COUNT(*) as total_records FROM raw.trip_data;"
echo.

echo Checking sample records...
docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT id, pickup_datetime, trip_duration FROM raw.trip_data LIMIT 5;"
echo.

echo Checking batch metadata...
docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT batch_id, status, records_processed, created_at FROM processed.batch_metadata ORDER BY created_at DESC LIMIT 5;"
echo.

echo ==========================================
echo Analysis
echo ==========================================
echo.
echo If you see records above, the data already exists!
echo The ingestion showed "0 records inserted" because of 
echo duplicate IDs (ON CONFLICT DO NOTHING).
echo.
echo Options:
echo 1. The data is already there - proceed to Spark processing
echo    Run: scripts\run_spark_processing_simple.bat
echo.
echo 2. Clear old data and re-ingest
echo    Run: scripts\clear_and_reingest.bat
echo.
pause