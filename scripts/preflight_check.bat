@echo off
echo ==========================================
echo Pre-Flight Check
echo ==========================================
echo.

set READY=1

echo Checking services...
echo.

docker ps --format "table {{.Names}}\t{{.Status}}" | findstr nyc-taxi

echo.
echo ==========================================
echo Data Check
echo ==========================================
echo.

for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2^>nul') do set RAW_COUNT=%%i

if "%RAW_COUNT%"=="" (
    echo X No data in raw.trip_data
    echo   Run monthly ingestion first
    set READY=0
) else (
    echo √ Raw data: %RAW_COUNT% records
)

echo.
echo ==========================================
echo Spark Cluster Check
echo ==========================================
echo.

docker ps | findstr nyc-taxi-spark-master >nul 2>&1
if errorlevel 1 (
    echo X Spark master NOT running
    set READY=0
) else (
    echo √ Spark master running
)

docker ps | findstr nyc-taxi-spark-worker >nul 2>&1
if errorlevel 1 (
    echo X Spark worker NOT running
    set READY=0
) else (
    echo √ Spark worker running
)

echo.
echo Open http://localhost:8081 to verify worker is connected
echo.

echo ==========================================
if %READY%==1 (
    echo √ READY TO PROCESS
    echo.
    echo Run: scripts\run_spark_processing_simple.bat
) else (
    echo X NOT READY
    echo.
    echo Fix the issues above first
)
echo ==========================================
echo.
pause