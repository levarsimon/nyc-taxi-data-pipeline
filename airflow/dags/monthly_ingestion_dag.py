"""
Monthly Data Ingestion DAG

This DAG runs monthly to ingest new NYC Taxi data.
"""

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import logging
import os
import sys

logger = logging.getLogger(__name__)

# Default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
}


def check_data_availability(**context):
    """Check if new data is available for ingestion"""
    #import os
    data_path = '/opt/airflow/data/raw/train.csv'
    
    if not os.path.exists(data_path):
        logger.error(f"Data file not found: {data_path}")
        raise FileNotFoundError(f"Data file not found: {data_path}")
    
    file_size = os.path.getsize(data_path)
    logger.info(f"Data file found: {data_path} ({file_size:,} bytes)")
    
    context['task_instance'].xcom_push(key='data_file', value=data_path)
    return data_path


def run_ingestion_task(**context):
    """Run ingestion service"""
    #import sys
    import subprocess
    
    # Install required packages in Airflow if not already installed
    subprocess.check_call([
        sys.executable, '-m', 'pip', 'install', '--quiet',
        'pandas==2.1.0', 'psycopg2-binary==2.9.7', 'minio==7.1.17'
    ])
    
    # Add the ingestion service directory to path
    sys.path.insert(0, '/opt/airflow/microservices/ingestion')
    
    # Set environment variables for the service
    os.environ['POSTGRES_HOST'] = 'postgres'
    os.environ['POSTGRES_PORT'] = '5432'
    os.environ['POSTGRES_USER'] = 'taxiuser'
    os.environ['POSTGRES_PASSWORD'] = 'taxipass'
    os.environ['POSTGRES_DB'] = 'nyc_taxi'
    os.environ['MINIO_ENDPOINT'] = 'minio:9000'
    os.environ['MINIO_ACCESS_KEY'] = 'minioadmin'
    os.environ['MINIO_SECRET_KEY'] = 'minioadmin'
    os.environ['MINIO_BUCKET'] = 'raw-data'
    
    file_path = '/opt/airflow/data/raw/train.csv'
    logger.info(f"Starting ingestion from: {file_path}")
    
    # Import and run the ingestion service
    from ingestion_service import DataIngestionService
    
    service = DataIngestionService()
    stats = service.ingest_csv(file_path)
    
    logger.info(f"Ingestion completed successfully!")
    logger.info(f"Batch ID: {stats['batch_id']}")
    logger.info(f"Records inserted: {stats['records_inserted']:,}")
    logger.info(f"Pass rate: {stats['validation_stats']['pass_rate']:.2%}")
    
    return stats


def validate_ingestion(**context):
    """Validate that ingestion completed successfully"""
    import psycopg2
    
    conn = psycopg2.connect(
        host='postgres',
        port=5432,
        database='nyc_taxi',
        user='taxiuser',
        password='taxipass'
    )
    
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM raw.trip_data")
    count = cursor.fetchone()[0]
    
    cursor.close()
    conn.close()
    
    logger.info(f"Total records in raw.trip_data: {count:,}")
    
    if count == 0:
        raise ValueError("No records found after ingestion")
    
    return count


# Create DAG
with DAG(
    'monthly_ingestion',
    default_args=default_args,
    description='Monthly ingestion of NYC Taxi data',
    schedule_interval='0 0 1 * *',  # Run on 1st day of each month
    catchup=False,
    tags=['ingestion', 'monthly'],
) as dag:
    
    # Task 1: Check data availability
    check_data = PythonOperator(
        task_id='check_data_availability',
        python_callable=check_data_availability,
        provide_context=True,
    )
    
    # Task 2: Run ingestion service
    run_ingestion = PythonOperator(
        task_id='run_ingestion_service',
        python_callable=run_ingestion_task,
        provide_context=True,
    )
    
    # Task 3: Validate ingestion
    validate = PythonOperator(
        task_id='validate_ingestion',
        python_callable=validate_ingestion,
        provide_context=True,
    )
    
    # Task 4: Send notification (placeholder)
    notify = BashOperator(
        task_id='send_notification',
        bash_command='echo "Ingestion completed successfully at $(date)"',
    )
    
    # Define task dependencies
    check_data >> run_ingestion >> validate >> notify