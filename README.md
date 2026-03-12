# NYC Taxi Trip Duration - Batch Processing Data Pipeline

## Project Overview
This project implements a batch-processing data architecture for processing NYC Taxi Trip Duration data. The system is designed to handle millions of records using microservices architecture, containerization, and Infrastructure as Code principles.

## Quick Start (For detailed setup guide refer to docs/SETUP_GUIDE.md)

```bash
# Clone repository
git clone https://github.com/levarsimon/nyc-taxi-data-pipeline.git
cd nyc-taxi-data-pipeline

# Download NYC Taxi data from https://www.kaggle.com/datasets/yasserh/nyc-taxi-trip-duration
# Extract NYC.csv from NYC.csv.zip
# Rename NYC.csv to train.csv
# Place train.csv in ./data/raw/

# Start all services
docker-compose up -d

# Access services
# Airflow: http://localhost:8080
# API: http://localhost:8000/docs
# MinIO: http://localhost:9001

# Run initial data ingestion
docker-compose exec airflow airflow dags trigger monthly_ingestion

# RUN QUARTERLY PROCESSING
# Windows
scripts/run_spark_processing.bat

# Mac
chmod +x scripts/run_spark_processing.sh    # make the script executable
./scripts/run_spark_processing.sh     # run the script
```