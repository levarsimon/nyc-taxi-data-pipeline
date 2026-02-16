@echo off
echo ==========================================
echo NYC Taxi Data - Spark Processing (Fixed)
echo ==========================================
echo.

echo [1/4] Checking data exists in PostgreSQL...
for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2^>nul') do set COUNT=%%i
if "%COUNT%"=="" (
    echo ERROR: Cannot query database or no data found
    echo Run monthly ingestion first
    pause
    exit /b 1
)
echo √ Found %COUNT% records ready for processing
echo.

echo [2/4] Downloading PostgreSQL driver to Spark container...
docker exec nyc-taxi-spark-master sh -c "mkdir -p /tmp/jars && curl -L -o /tmp/jars/postgresql-42.6.0.jar https://jdbc.postgresql.org/download/postgresql-42.6.0.jar" 2>nul
if errorlevel 1 (
    echo Installing curl in Spark container...
    docker exec -u root nyc-taxi-spark-master apt-get update -qq
    docker exec -u root nyc-taxi-spark-master apt-get install -y -qq curl
    docker exec nyc-taxi-spark-master sh -c "mkdir -p /tmp/jars && curl -L -o /tmp/jars/postgresql-42.6.0.jar https://jdbc.postgresql.org/download/postgresql-42.6.0.jar"
)
echo √ PostgreSQL driver downloaded
echo.

echo [3/4] Submitting Spark job...
echo This will take 10-20 minutes for %COUNT% records
echo.
echo Watch progress in another window with:
echo   docker-compose logs -f spark-master
echo.
echo Starting now...
echo.

REM Run the Spark job with local JAR (no package resolution needed)
docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit ^
  --master spark://spark-master:7077 ^
  --deploy-mode client ^
  --executor-memory 2g ^
  --driver-memory 1g ^
  --conf spark.sql.shuffle.partitions=200 ^
  --jars /tmp/jars/postgresql-42.6.0.jar ^
  /opt/spark-apps/processing_service.py

set EXIT_CODE=%ERRORLEVEL%

echo.
echo ==========================================

if %EXIT_CODE% equ 0 (
    echo [4/4] Verifying results...
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
    echo ★ CONGRATULATIONS! ★
    echo Your complete data pipeline is working!
    echo.
    echo Next steps:
    echo   1. Query via API: http://localhost:8000/docs
    echo   2. View sample data:
    echo      docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi
    echo      SELECT * FROM processed.trip_features LIMIT 5;
    echo   3. Check aggregations:
    echo      SELECT * FROM aggregated.hourly_stats LIMIT 10;
    echo.
    echo Your portfolio project is complete!
    echo ==========================================
) else (
    echo X Spark Processing Failed
    echo.
    echo Exit code: %EXIT_CODE%
    echo.
    echo Check logs for details:
    echo   docker-compose logs spark-master
    echo.
    echo ==========================================
)

pause
exit /b %EXIT_CODE%