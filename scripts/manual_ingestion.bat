@echo off
echo ==========================================
echo Manual Ingestion Test
echo ==========================================
echo.

echo Step 1: Verify train.csv exists...
docker exec nyc-taxi-airflow-scheduler ls -lh /opt/airflow/data/raw/train.csv 2>nul
if errorlevel 1 (
    echo ERROR: train.csv not found in /opt/airflow/data/raw/
    echo.
    echo Make sure you have placed train.csv in the data/raw/ folder
    echo in your project directory.
    pause
    exit /b 1
)
echo √ Found train.csv
echo.

echo Step 2: Check database connection...
docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT 1 as test;" 2>nul
if errorlevel 1 (
    echo ERROR: Cannot connect to PostgreSQL from host
    echo.
    echo Checking if PostgreSQL is running...
    docker-compose ps postgres
    pause
    exit /b 1
)
echo √ Database connection OK
echo.

echo Step 2b: Check Python can connect from Airflow...
docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; conn = psycopg2.connect(host='postgres', port=5432, database='nyc_taxi', user='taxiuser', password='taxipass'); print('Python connection: OK'); conn.close()" 2>nul
if errorlevel 1 (
    echo ERROR: Python cannot connect to PostgreSQL from Airflow
    echo.
    echo This means psycopg2 is not working properly.
    echo.
    echo Try:
    echo 1. Run rebuild_airflow.bat again
    echo 2. Check if custom Airflow image was built:
    echo    docker images | findstr nyc-taxi
    echo.
    pause
    exit /b 1
)
echo √ Python connection OK
echo.

echo Step 3: Clear any old data (optional - comment out if you want to keep existing data)...
REM docker exec postgres psql -U taxiuser -d nyc_taxi -c "TRUNCATE raw.trip_data CASCADE;"
echo Skipping cleanup (keeping existing data if any)
echo.

echo Step 4: Running ingestion manually...
echo This may take 5-15 minutes depending on file size
echo.
echo Press Ctrl+C to cancel, or wait for completion...
echo.

docker exec -e POSTGRES_HOST=postgres -e POSTGRES_PORT=5432 -e POSTGRES_USER=taxiuser -e POSTGRES_PASSWORD=taxipass -e POSTGRES_DB=nyc_taxi -e MINIO_ENDPOINT=minio:9000 -e MINIO_ACCESS_KEY=minioadmin -e MINIO_SECRET_KEY=minioadmin -e MINIO_BUCKET=raw-data nyc-taxi-airflow-scheduler python /opt/airflow/microservices/ingestion/ingestion_service.py /opt/airflow/data/raw/train.csv

set EXIT_CODE=%ERRORLEVEL%

echo.
echo ==========================================

if %EXIT_CODE% equ 0 (
    echo Step 5: Verifying data was inserted...
    echo.
    
    for /f %%i in ('docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -t -c "SELECT COUNT(*) FROM raw.trip_data;" 2^>nul') do set COUNT=%%i
    
    if "%COUNT%"=="" (
        echo ERROR: Could not query database
    ) else (
        echo √ SUCCESS!
        echo.
        echo Total records in database: %COUNT%
        echo.
        echo Sample data:
        docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT id, pickup_datetime, trip_duration FROM raw.trip_data LIMIT 3;"
    )
    
    echo.
    echo ==========================================
    echo Ingestion completed successfully!
    echo.
    echo You can now run Spark processing:
    echo   scripts\run_spark_processing_simple.bat
    echo ==========================================
) else (
    echo ERROR: Ingestion failed with exit code %EXIT_CODE%
    echo.
    echo Check the output above for error messages
    echo.
    echo Common issues:
    echo   1. train.csv not found or in wrong location
    echo   2. Database connection failed
    echo   3. Python package missing (pandas, psycopg2, minio)
    echo   4. Out of memory
    echo.
    echo Try running with a smaller test file first:
    echo   docker exec nyc-taxi-airflow-scheduler head -1001 /opt/airflow/data/raw/train.csv ^> /opt/airflow/data/raw/test.csv
    echo   docker exec nyc-taxi-airflow-scheduler python /opt/airflow/microservices/ingestion/ingestion_service.py /opt/airflow/data/raw/test.csv
    echo ==========================================
)

pause
exit /b %EXIT_CODE%