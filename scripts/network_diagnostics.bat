@echo off
REM Network Diagnostics for NYC Taxi Pipeline

echo ==========================================
echo Network Diagnostics
echo ==========================================
echo.

echo Checking Docker network...
docker network ls | findstr taxi-network
if errorlevel 1 (
    echo ERROR: taxi-network not found
    echo Creating network...
    docker network create taxi-network
)

echo.
echo Checking which containers are on taxi-network...
docker network inspect taxi-network --format "{{range .Containers}}{{.Name}} {{end}}"

echo.
echo ==========================================
echo Container Connectivity Tests
echo ==========================================

echo.
echo 1. Testing from Spark Master to PostgreSQL...
docker exec nyc-taxi-spark-master sh -c "apt-get update -qq && apt-get install -y -qq postgresql-client > /dev/null 2>&1 && psql -h postgres -U taxiuser -d nyc_taxi -c 'SELECT 1;'" 2>nul
if errorlevel 1 (
    echo    X FAILED
    echo.
    echo    Trying to install psql and test again...
    docker exec nyc-taxi-spark-master sh -c "apt-get update && apt-get install -y postgresql-client"
    docker exec nyc-taxi-spark-master psql -h postgres -U taxiuser -d nyc_taxi -c "SELECT 1;"
) else (
    echo    √ SUCCESS
)

echo.
echo 2. Testing from Airflow to PostgreSQL...
docker exec nyc-taxi-airflow-scheduler psql postgresql://taxiuser:taxipass@postgres:5432/nyc_taxi -c "SELECT 1;" 2>nul
if errorlevel 1 (
    echo    X FAILED
) else (
    echo    √ SUCCESS
)

echo.
echo 3. Testing from Spark to MinIO...
docker exec nyc-taxi-spark-master sh -c "apt-get install -y -qq curl > /dev/null 2>&1 && curl -s http://minio:9000/minio/health/live" 2>nul
if errorlevel 1 (
    echo    X FAILED
) else (
    echo    √ SUCCESS
)

echo.
echo ==========================================
echo Network Configuration
echo ==========================================
echo.

echo Spark Master IP:
docker inspect nyc-taxi-spark-master --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"

echo PostgreSQL IP:
docker inspect nyc-taxi-postgres --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"

echo MinIO IP:
docker inspect nyc-taxi-minio --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"

echo.
echo ==========================================
echo Recommendations
echo ==========================================
echo.
echo If connectivity tests fail:
echo 1. Restart all services: docker-compose restart
echo 2. Check firewall settings
echo 3. Ensure all containers are on taxi-network
echo 4. Check docker-compose.yml network configuration
echo.
pause