@echo off
REM Test Spark Setup - Windows Version

echo ==========================================
echo Testing Spark Setup
echo ==========================================
echo.

echo 1. Checking if Spark master is running...
docker ps | findstr nyc-taxi-spark-master >nul 2>&1
if errorlevel 1 (
    echo    X Spark master is NOT running
    echo    Start it with: docker-compose up -d spark-master
    pause
    exit /b 1
)
echo    √ Spark master is running

echo.
echo 2. Checking if Spark worker is connected...
docker ps | findstr nyc-taxi-spark-worker >nul 2>&1
if errorlevel 1 (
    echo    X Spark worker is NOT running
    echo    Start it with: docker-compose up -d spark-worker
    pause
    exit /b 1
)
echo    √ Spark worker is running

echo.
echo 3. Checking if processing script exists...
docker exec nyc-taxi-spark-master test -f /opt/spark-apps/processing_service.py >nul 2>&1
if errorlevel 1 (
    echo    X Processing script NOT found
    echo    Check volume mount in docker-compose.yml
    pause
    exit /b 1
)
echo    √ Processing script found

echo.
echo 4. Testing simple Spark job...
docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit --master local[1] --deploy-mode client --class org.apache.spark.examples.SparkPi /opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar 10 >nul 2>&1
if errorlevel 1 (
    echo    X Simple Spark job failed
    pause
    exit /b 1
)
echo    √ Simple Spark job succeeded

echo.
echo 5. Checking PostgreSQL connectivity...
docker exec postgres psql -U taxiuser -d nyc_taxi -c "SELECT 1;" >nul 2>&1
if errorlevel 1 (
    echo    X Cannot connect to PostgreSQL
    echo    Make sure PostgreSQL is running
    pause
    exit /b 1
)
echo    √ Can connect to PostgreSQL from host

echo.
echo 6. Checking data in database...
for /f %%i in ('docker exec postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2^>nul') do set COUNT=%%i
if "%COUNT%"=="" (
    echo    X No data found in raw.trip_data
    echo    Run monthly ingestion first
    pause
    exit /b 1
)
echo    √ Found %COUNT% records in raw.trip_data

echo.
echo ==========================================
echo √ All checks passed!
echo ==========================================
echo.
echo Ready to run Spark processing.
echo.
echo Run: scripts\run_spark_processing.bat
echo.
pause