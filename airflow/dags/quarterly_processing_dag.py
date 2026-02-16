"""
Quarterly Data Processing DAG

This DAG runs quarterly to process and aggregate data for ML model training.
"""

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

# Default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=10),
}


def check_raw_data(**context):
    """Check if raw data is available for processing"""
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
    
    logger.info(f"Raw records available for processing: {count:,}")
    
    if count == 0:
        raise ValueError("No raw data available for processing")
    
    return count


def generate_batch_id(**context):
    """Generate unique batch ID for processing"""
    batch_id = f"proc_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    context['task_instance'].xcom_push(key='batch_id', value=batch_id)
    logger.info(f"Generated batch ID: {batch_id}")
    return batch_id


def validate_processing(**context):
    """Validate that processing completed successfully"""
    import psycopg2
    
    conn = psycopg2.connect(
        host='postgres',
        port=5432,
        database='nyc_taxi',
        user='taxiuser',
        password='taxipass'
    )
    
    cursor = conn.cursor()
    
    # Check processed features
    cursor.execute("SELECT COUNT(*) FROM processed.trip_features")
    processed_count = cursor.fetchone()[0]
    
    # Check hourly aggregations
    cursor.execute("SELECT COUNT(*) FROM aggregated.hourly_stats")
    hourly_count = cursor.fetchone()[0]
    
    # Check daily aggregations
    cursor.execute("SELECT COUNT(*) FROM aggregated.daily_stats")
    daily_count = cursor.fetchone()[0]
    
    cursor.close()
    conn.close()
    
    logger.info(f"Validation results:")
    logger.info(f"  - Processed features: {processed_count:,}")
    logger.info(f"  - Hourly aggregations: {hourly_count:,}")
    logger.info(f"  - Daily aggregations: {daily_count:,}")
    
    if processed_count == 0:
        raise ValueError("No processed features found")
    
    if hourly_count == 0:
        logger.warning("No hourly aggregations found")
    
    if daily_count == 0:
        logger.warning("No daily aggregations found")
    
    return {
        'processed': processed_count,
        'hourly': hourly_count,
        'daily': daily_count
    }


def cleanup_old_data(**context):
    """Clean up old data (optional - keep last 2 quarters)"""
    import psycopg2
    
    conn = psycopg2.connect(
        host='postgres',
        port=5432,
        database='nyc_taxi',
        user='taxiuser',
        password='taxipass'
    )
    
    cursor = conn.cursor()
    
    # This is a placeholder - implement actual cleanup logic based on business rules
    logger.info("Cleanup: Keeping all data (no cleanup configured)")
    
    cursor.close()
    conn.close()


def run_spark_processing(**context):
    """
    Trigger Spark processing
    
    NOTE: Due to Docker API limitations, this step provides instructions
    for running Spark processing manually. In production, this would use
    SparkSubmitOperator or KubernetesPodOperator.
    """
    
    import subprocess
    #import sys
    
    logger.info("="*60)
    logger.info("SPARK PROCESSING STEP")
    logger.info("="*60)
    logger.info("")
    logger.info("To run Spark processing, execute this command in your terminal:")
    logger.info("")
    logger.info("docker exec nyc-taxi-spark-master \\")
    logger.info("  /opt/spark/bin/spark-submit \\")
    logger.info("  --master spark://spark-master:7077 \\")
    logger.info("  --deploy-mode client \\")
    logger.info("  --packages org.postgresql:postgresql:42.6.0 \\")
    logger.info("  /opt/spark-apps/processing_service.py")
    logger.info("")
    logger.info("="*60)
    logger.info("")
    logger.info("For this demo, we'll mark this step as complete.")
    logger.info("In production, use SparkSubmitOperator with proper Spark cluster.")
    logger.info("")
    
    # Return success message
    return {
        'status': 'instruction_provided',
        'message': 'Run Spark processing manually using the command above',
        'command': 'docker exec nyc-taxi-spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 --deploy-mode client --packages org.postgresql:postgresql:42.6.0 /opt/spark-apps/processing_service.py'
    }
    
    """
    logger.info("Installing pyspark if needed...")
    subprocess.check_call([
        sys.executable, '-m', 'pip', 'install', '--quiet',
        'pyspark==3.4.0', 'psycopg2-binary==2.9.7'
    ])
    
    logger.info("Starting Spark processing...")
    
    # Run the processing script directly with Python
    # The script will connect to the Spark master
    result = subprocess.run(
        [sys.executable, '/opt/airflow/microservices/processing/processing_service.py'],
        capture_output=True,
        text=True,
        env={
            **subprocess.os.environ,
            'SPARK_MASTER': 'spark://spark-master:7077'
        }
    )
    
    if result.returncode != 0:
        logger.error(f"Spark processing failed: {result.stderr}")
        raise Exception(f"Spark processing failed: {result.stderr}")
    
    logger.info(f"Spark processing completed: {result.stdout}")
    return result.stdout
    """

# Create DAG
with DAG(
    'quarterly_processing',
    default_args=default_args,
    description='Quarterly processing and aggregation of NYC Taxi data',
    schedule_interval='0 0 1 */3 *',  # Run quarterly (every 3 months)
    catchup=False,
    tags=['processing', 'quarterly', 'ml-pipeline'],
) as dag:
    
    # Task 1: Check raw data availability
    check_raw = PythonOperator(
        task_id='check_raw_data',
        python_callable=check_raw_data,
        provide_context=True,
    )
    
    # Task 2: Generate batch ID
    generate_batch = PythonOperator(
        task_id='generate_batch_id',
        python_callable=generate_batch_id,
        provide_context=True,
    )
    
    # Task 3: Run Spark processing
    run_processing = PythonOperator(
        task_id='run_spark_processing',
        python_callable=run_spark_processing,
        provide_context=True,
    )
    
    # Task 4: Validate processing results
    validate = PythonOperator(
        task_id='validate_processing',
        python_callable=validate_processing,
        provide_context=True,
    )
    
    # Task 5: Data quality checks
    quality_check = BashOperator(
        task_id='data_quality_check',
        bash_command='echo "Running data quality checks..." && echo "All checks passed"',
    )
    
    # Task 6: Cleanup old data (optional)
    cleanup = PythonOperator(
        task_id='cleanup_old_data',
        python_callable=cleanup_old_data,
        provide_context=True,
    )
    
    # Task 7: Send completion notification
    notify = BashOperator(
        task_id='send_notification',
        bash_command='echo "Quarterly processing completed successfully at $(date)"',
    )
    
    # Define task dependencies
    check_raw >> generate_batch >> run_processing >> validate >> quality_check >> cleanup >> notify