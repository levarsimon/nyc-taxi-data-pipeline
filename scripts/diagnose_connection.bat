@echo off
echo ==========================================
echo PostgreSQL Connection Diagnostics
echo ==========================================
echo.

echo [Test 1] Is PostgreSQL container running?
docker-compose ps postgres
echo.

echo [Test 2] Can we connect to PostgreSQL from host?
docker exec nyc-taxi-postgres psql -U taxiuser -d nyc_taxi -c "SELECT version();"
if errorlevel 1 (
    echo X FAILED
    echo PostgreSQL is not responding or credentials are wrong
    pause
    exit /b 1
) else (
    echo √ SUCCESS
)
echo.

echo [Test 3] Is psycopg2 installed in Airflow?
docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; print('psycopg2 version:', psycopg2.__version__)"
if errorlevel 1 (
    echo X FAILED - psycopg2 not installed
    echo.
    echo The Airflow image was not rebuilt properly.
    echo.
    echo Solution: Run rebuild_airflow.bat again
    pause
    exit /b 1
) else (
    echo √ SUCCESS
)
echo.

echo [Test 4] Can Python connect to PostgreSQL from Airflow?
docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; conn = psycopg2.connect(host='postgres', port=5432, database='nyc_taxi', user='taxiuser', password='taxipass'); cursor = conn.cursor(); cursor.execute('SELECT COUNT(*) FROM raw.trip_data'); count = cursor.fetchone()[0]; print(f'Connection successful! Records in database: {count}'); conn.close()"
if errorlevel 1 (
    echo X FAILED
    echo.
    echo Python has psycopg2 but cannot connect to database.
    echo.
    echo Possible issues:
    echo 1. Network issue between containers
    echo 2. PostgreSQL not accepting connections
    echo 3. Wrong credentials
    echo.
    echo Checking detailed error...
    docker exec nyc-taxi-airflow-scheduler python -c "import psycopg2; psycopg2.connect(host='postgres', port=5432, database='nyc_taxi', user='taxiuser', password='taxipass')"
    pause
    exit /b 1
) else (
    echo √ SUCCESS
)
echo.

echo [Test 5] Check what Airflow image is actually running
docker inspect nyc-taxi-airflow-scheduler --format "{{.Config.Image}}"
echo.

echo [Test 6] Verify custom image was built
docker images | findstr "nyc-taxi-data-pipeline"
echo.

echo ==========================================
echo Summary
echo ==========================================
echo.
echo If all tests passed:
echo   Your connection is working!
echo   Run: scripts\manual_ingestion.bat
echo.
echo If Test 3 or 4 failed:
echo   Airflow is using the wrong image
echo   Solution:
echo   1. docker-compose down
echo   2. scripts\rebuild_airflow.bat
echo   3. docker-compose up -d
echo.
pause