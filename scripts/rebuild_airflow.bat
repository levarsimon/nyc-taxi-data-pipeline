@echo off
echo ==========================================
echo Rebuild Airflow with Required Packages
echo ==========================================
echo.

echo This will:
echo 1. Stop Airflow services
echo 2. Rebuild custom Airflow image with all packages
echo 3. Restart Airflow services
echo.
echo This may take 3-5 minutes...
echo.
pause

echo Step 1: Stopping Airflow services...
docker-compose stop airflow-scheduler airflow-webserver
echo.

echo Step 2: Building custom Airflow image...
echo (This includes pandas, psycopg2-binary, minio, pyspark)
echo.
docker-compose build --no-cache airflow-scheduler airflow-webserver
if errorlevel 1 (
    echo.
    echo ERROR: Build failed!
    echo Check the output above for errors.
    pause
    exit /b 1
)
echo.

echo Step 3: Starting Airflow services...
docker-compose up -d airflow-scheduler airflow-webserver
echo.

echo Step 4: Waiting for Airflow to be ready (30 seconds)...
timeout /t 30 /nobreak >nul
echo.

echo Step 5: Verifying packages are installed...
echo.
docker exec nyc-taxi-airflow-scheduler python -c "import pandas; print('pandas:', pandas.__version__)"
docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; print('psycopg2:', psycopg2.__version__)"
docker exec nyc-taxi-airflow-scheduler python -c "import minio; print('minio: OK')"
echo.

echo Step 6: Testing database connection...
docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; conn = psycopg2.connect(host='postgres', port=5432, database='nyc_taxi', user='taxiuser', password='taxipass'); print('Database connection: OK'); conn.close()"
if errorlevel 1 (
    echo.
    echo ERROR: Database connection failed!
    echo.
    echo Check if PostgreSQL is running:
    echo   docker-compose ps postgres
    echo.
    pause
    exit /b 1
)
echo.

echo ==========================================
echo √ Airflow Rebuilt Successfully!
echo ==========================================
echo.
echo Packages installed:
echo   - pandas
echo   - psycopg2-binary
echo   - minio
echo   - pyspark
echo.
echo Database connection: Working
echo.
echo Next steps:
echo 1. Open Airflow UI: http://localhost:8080
echo 2. Run manual ingestion: scripts\manual_ingestion.bat
echo 3. Or trigger DAG in Airflow UI
echo.
echo ==========================================
pause