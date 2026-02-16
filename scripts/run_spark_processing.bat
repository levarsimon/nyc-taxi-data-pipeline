@echo off
REM Run Spark Processing Manually - Windows Version

echo ==========================================
echo NYC Taxi Data - Spark Processing
echo ==========================================
echo.

REM Check if Spark master is running
docker ps | findstr nyc-taxi-spark-master >nul 2>&1
if errorlevel 1 (
    echo ERROR: Spark master is not running
    echo Start it with: docker-compose up -d spark-master
    pause
    exit /b 1
)

echo Submitting Spark job to cluster...
echo.

REM Run spark-submit in the Spark master container
docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client --executor-memory 2g --driver-memory 1g --packages org.postgresql:postgresql:42.6.0 /opt/spark-apps/processing_service.py

if errorlevel 1 (
    echo.
    echo ==========================================
    echo X Spark processing failed
    echo.
    echo Check logs with:
    echo   docker-compose logs spark-master
    echo ==========================================
    pause
    exit /b 1
)

echo.
echo ==========================================
echo √ Spark processing completed successfully!
echo.
echo Verify the results:
echo   docker-compose exec postgres psql -U taxiuser -d nyc_taxi
echo   SELECT COUNT(*) FROM processed.trip_features;
echo   SELECT COUNT(*) FROM aggregated.hourly_stats;
echo   SELECT COUNT(*) FROM aggregated.daily_stats;
echo ==========================================
echo.
pause