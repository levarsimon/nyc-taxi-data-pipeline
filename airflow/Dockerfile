FROM apache/airflow:2.7.0-python3.10

USER root

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        postgresql-client \
        python3-dev \
        libpq-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER airflow

# Upgrade pip first
RUN pip install --upgrade pip

# Install Python packages needed for DAGs one by one to better handle errors
RUN pip install --no-cache-dir pandas==2.1.0
RUN pip install --no-cache-dir psycopg2-binary==2.9.7
RUN pip install --no-cache-dir minio==7.1.17
RUN pip install --no-cache-dir pyspark==3.4.0

# Verify installations
RUN python -c "import pandas; import psycopg2; import minio; print('All packages installed successfully')"
