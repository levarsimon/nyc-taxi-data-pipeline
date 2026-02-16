# NYC Taxi Trip Duration - Batch Processing Data Pipeline

## Project Overview
This project implements a production-ready batch-processing data architecture for processing NYC Taxi Trip Duration data. The system is designed to handle millions of records using microservices architecture, containerization, and Infrastructure as Code principles.

## Quick Start

```bash
# Clone repository
git clone <your-repo-url>
cd nyc-taxi-data-pipeline

# Download NYC Taxi data from Kaggle
# Place train.csv in ./data/raw/

# Start all services
docker-compose up -d

# Access services
# Airflow: http://localhost:8080
# API: http://localhost:8000
# MinIO: http://localhost:9001

# Run initial data ingestion
docker-compose exec airflow airflow dags trigger monthly_ingestion

# Run quarterly processing
docker-compose exec airflow airflow dags trigger quarterly_processing
```
