FROM apache/airflow:2.7.0-python3.10

USER root

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Install Python packages needed for DAGs
RUN pip install --no-cache-dir \
    pandas==2.1.0 \
    psycopg2-binary==2.9.7 \
    minio==7.1.17 \
    pyspark==3.4.0
