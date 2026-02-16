@echo off
REM Simplified Spark Processing Script

echo ==========================================
echo NYC Taxi Data - Spark Processing
echo ==========================================
echo.

REM Check Spark is running
docker ps | findstr nyc-taxi-spark-master >nul 2>&1
if errorlevel 1 (
    echo ERROR: Spark master is not running
    echo Start with: docker-compose up -d spark-master spark-worker
    pause
    exit /b 1
)

echo [1/3] Checking data exists in PostgreSQL...
for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2^>nul') do set COUNT=%%i
if "%COUNT%"=="" (
    echo ERROR: Cannot query database or no data found
    echo Run monthly ingestion first
    pause
    exit /b 1
)
echo √ Found %COUNT% records ready for processing
echo.

echo [2/3] Submitting Spark job...
echo This will take 10-20 minutes for %COUNT% records
echo.
echo Watch progress in another window with:
echo   docker-compose logs -f spark-master
echo.
echo Starting now...
echo.

REM Run the Spark job
docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit ^
  --master spark://spark-master:7077 ^
  --deploy-mode client ^
  --executor-memory 2g ^
  --driver-memory 1g ^
  --conf spark.sql.shuffle.partitions=200 ^
  --packages org.postgresql:postgresql:42.6.0 ^
  /opt/spark-apps/processing_service.py

set EXIT_CODE=%ERRORLEVEL%

echo.
echo ==========================================

if %EXIT_CODE% equ 0 (
    echo [3/3] Verifying results...
    echo.
    
    for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM processed.trip_features;" 2^>nul') do set PROC_COUNT=%%i
    for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM aggregated.hourly_stats;" 2^>nul') do set HOUR_COUNT=%%i
    for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM aggregated.daily_stats;" 2^>nul') do set DAILY_COUNT=%%i
    
    echo √ Spark Processing Completed Successfully!
    echo.
    echo Results:
    echo   - Processed features: %PROC_COUNT% records
    echo   - Hourly aggregations: %HOUR_COUNT% records
    echo   - Daily aggregations: %DAILY_COUNT% records
    echo.
    echo ==========================================
    echo.
    echo Next steps:
    echo   1. Query via API: http://localhost:8000/docs
    echo   2. Check database:
    echo      docker exec -it postgres psql -U taxiuser -d nyc_taxi
    echo      SELECT * FROM processed.trip_features LIMIT 5;
    echo.
    echo Your complete data pipeline is now working!
    echo ==========================================
) else (
    echo X Spark Processing Failed
    echo.
    echo Exit code: %EXIT_CODE%
    echo.
    echo Troubleshooting:
    echo   1. Check Spark logs:
    echo      docker-compose logs spark-master
    echo      docker-compose logs spark-worker
    echo.
    echo   2. Check if Spark master is healthy:
    echo      http://localhost:8081
    echo.
    echo   3. Verify worker is connected to master
    echo.
    echo   4. Check PostgreSQL is accessible:
    echo      docker exec postgres psql -U taxiuser -d nyc_taxi -c "SELECT 1;"
    echo.
    echo   5. Try with reduced memory:
    echo      Edit the script and change:
    echo      --executor-memory 1g
    echo      --driver-memory 512m
    echo.
    echo ==========================================
)

pause
exit /b %EXIT_CODE%