"""
NYC Taxi Data Ingestion Service

This service handles the ingestion of raw CSV data into the system.
It validates data, stores raw files in MinIO, and loads structured data into PostgreSQL.
"""

import os
import sys
import logging
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from minio import Minio
from minio.error import S3Error
from datetime import datetime
import hashlib
from io import BytesIO

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DataIngestionService:
    """Handles data ingestion from CSV to MinIO and PostgreSQL"""
    
    def __init__(self):
        """Initialize connections to PostgreSQL and MinIO"""
        # PostgreSQL configuration
        self.pg_config = {
            'host': os.getenv('POSTGRES_HOST', 'localhost'),
            'port': os.getenv('POSTGRES_PORT', '5432'),
            'user': os.getenv('POSTGRES_USER', 'taxiuser'),
            'password': os.getenv('POSTGRES_PASSWORD', 'taxipass'),
            'database': os.getenv('POSTGRES_DB', 'nyc_taxi')
        }
        
        # MinIO configuration
        self.minio_endpoint = os.getenv('MINIO_ENDPOINT', 'localhost:9000')
        self.minio_access_key = os.getenv('MINIO_ACCESS_KEY', 'minioadmin')
        self.minio_secret_key = os.getenv('MINIO_SECRET_KEY', 'minioadmin')
        self.minio_bucket = os.getenv('MINIO_BUCKET', 'raw-data')
        
        # Initialize MinIO client
        self.minio_client = Minio(
            self.minio_endpoint,
            access_key=self.minio_access_key,
            secret_key=self.minio_secret_key,
            secure=False
        )
        
        # Batch configuration
        self.batch_size = int(os.getenv('BATCH_SIZE', 10000))
        
    def connect_postgres(self):
        """Create PostgreSQL connection"""
        try:
            conn = psycopg2.connect(**self.pg_config)
            logger.info("Successfully connected to PostgreSQL")
            return conn
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise
    
    def validate_data(self, df):
        """
        Validate data quality
        
        Args:
            df: Pandas DataFrame to validate
            
        Returns:
            tuple: (valid_df, validation_stats)
        """
        logger.info("Starting data validation...")
        
        initial_count = len(df)
        validation_stats = {
            'initial_count': initial_count,
            'checks': []
        }
        
        # Check 1: Remove duplicates
        df = df.drop_duplicates(subset=['id'])
        duplicates_removed = initial_count - len(df)
        validation_stats['checks'].append({
            'check': 'duplicates',
            'removed': duplicates_removed
        })
        logger.info(f"Removed {duplicates_removed} duplicate records")
        
        # Check 2: Remove null critical fields
        critical_fields = ['id', 'pickup_datetime', 'dropoff_datetime']
        before = len(df)
        df = df.dropna(subset=critical_fields)
        nulls_removed = before - len(df)
        validation_stats['checks'].append({
            'check': 'null_critical_fields',
            'removed': nulls_removed
        })
        logger.info(f"Removed {nulls_removed} records with null critical fields")
        
        # Check 3: Validate trip duration (should be positive)
        before = len(df)
        df = df[df['trip_duration'] > 0]
        invalid_duration = before - len(df)
        validation_stats['checks'].append({
            'check': 'invalid_duration',
            'removed': invalid_duration
        })
        logger.info(f"Removed {invalid_duration} records with invalid duration")
        
        # Check 4: Validate coordinates (NYC area approximately)
        before = len(df)
        df = df[
            (df['pickup_longitude'].between(-74.3, -73.7)) &
            (df['pickup_latitude'].between(40.5, 41.0)) &
            (df['dropoff_longitude'].between(-74.3, -73.7)) &
            (df['dropoff_latitude'].between(40.5, 41.0))
        ]
        invalid_coords = before - len(df)
        validation_stats['checks'].append({
            'check': 'invalid_coordinates',
            'removed': invalid_coords
        })
        logger.info(f"Removed {invalid_coords} records with invalid coordinates")
        
        # Check 5: Validate passenger count
        before = len(df)
        df = df[(df['passenger_count'] > 0) & (df['passenger_count'] <= 9)]
        invalid_passengers = before - len(df)
        validation_stats['checks'].append({
            'check': 'invalid_passenger_count',
            'removed': invalid_passengers
        })
        logger.info(f"Removed {invalid_passengers} records with invalid passenger count")
        
        validation_stats['final_count'] = len(df)
        validation_stats['total_removed'] = initial_count - len(df)
        validation_stats['pass_rate'] = len(df) / initial_count if initial_count > 0 else 0
        
        logger.info(f"Validation complete. Pass rate: {validation_stats['pass_rate']:.2%}")
        
        return df, validation_stats
    
    def upload_to_minio(self, file_path, batch_id):
        """
        Upload raw CSV file to MinIO
        
        Args:
            file_path: Path to CSV file
            batch_id: Unique batch identifier
        """
        try:
            # Create bucket if it doesn't exist
            if not self.minio_client.bucket_exists(self.minio_bucket):
                self.minio_client.make_bucket(self.minio_bucket)
                logger.info(f"Created bucket: {self.minio_bucket}")
            
            # Generate object name with timestamp
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            object_name = f"raw/{timestamp}_{batch_id}_{os.path.basename(file_path)}"
            
            # Upload file
            self.minio_client.fput_object(
                self.minio_bucket,
                object_name,
                file_path
            )
            
            logger.info(f"Uploaded {file_path} to MinIO as {object_name}")
            return object_name
            
        except S3Error as e:
            logger.error(f"MinIO upload failed: {e}")
            raise
    
    def insert_to_postgres(self, df, batch_id):
        """
        Insert data into PostgreSQL in batches
        
        Args:
            df: Pandas DataFrame to insert
            batch_id: Unique batch identifier
        """
        conn = self.connect_postgres()
        cursor = conn.cursor()
        
        try:
            # Convert datetime columns
            df['pickup_datetime'] = pd.to_datetime(df['pickup_datetime'])
            df['dropoff_datetime'] = pd.to_datetime(df['dropoff_datetime'])
            
            # Add metadata columns
            df['ingestion_timestamp'] = datetime.now()
            df['ingestion_batch_id'] = batch_id
            
            # Prepare data for insertion
            columns = [
                'id', 'vendor_id', 'pickup_datetime', 'dropoff_datetime',
                'passenger_count', 'pickup_longitude', 'pickup_latitude',
                'dropoff_longitude', 'dropoff_latitude', 'store_and_fwd_flag',
                'trip_duration', 'ingestion_timestamp', 'ingestion_batch_id'
            ]
            
            # Insert in batches
            total_inserted = 0
            for i in range(0, len(df), self.batch_size):
                batch = df.iloc[i:i + self.batch_size]
                
                # Prepare values
                values = [
                    tuple(row) for row in batch[columns].values
                ]
                
                # Insert batch
                insert_query = f"""
                    INSERT INTO raw.trip_data ({', '.join(columns)})
                    VALUES %s
                    ON CONFLICT (id) DO NOTHING
                """
                
                execute_values(cursor, insert_query, values)
                total_inserted += cursor.rowcount
                
                logger.info(f"Inserted batch {i//self.batch_size + 1}: {cursor.rowcount} records")
            
            conn.commit()
            logger.info(f"Total records inserted: {total_inserted}")
            
            return total_inserted
            
        except Exception as e:
            conn.rollback()
            logger.error(f"PostgreSQL insertion failed: {e}")
            raise
        finally:
            cursor.close()
            conn.close()
    
    def log_batch_metadata(self, batch_id, status, records_processed, error_message=None):
        """Log batch processing metadata"""
        conn = self.connect_postgres()
        cursor = conn.cursor()
        
        try:
            if status == 'started':
                query = """
                    INSERT INTO processed.batch_metadata 
                    (batch_id, batch_type, start_time, status, records_processed)
                    VALUES (%s, %s, %s, %s, %s)
                """
                cursor.execute(query, (batch_id, 'ingestion', datetime.now(), 'running', 0))
            else:
                query = """
                    UPDATE processed.batch_metadata
                    SET end_time = %s, status = %s, records_processed = %s, error_message = %s
                    WHERE batch_id = %s
                """
                cursor.execute(query, (datetime.now(), status, records_processed, error_message, batch_id))
            
            conn.commit()
            logger.info(f"Logged batch metadata: {batch_id} - {status}")
            
        except Exception as e:
            conn.rollback()
            logger.error(f"Failed to log batch metadata: {e}")
        finally:
            cursor.close()
            conn.close()
    
    def ingest_csv(self, file_path):
        """
        Main ingestion pipeline
        
        Args:
            file_path: Path to CSV file to ingest
            
        Returns:
            dict: Ingestion statistics
        """
        # Generate unique batch ID
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        file_hash = hashlib.md5(file_path.encode()).hexdigest()[:8]
        batch_id = f"batch_{timestamp}_{file_hash}"
        
        logger.info(f"Starting ingestion for batch: {batch_id}")
        logger.info(f"File: {file_path}")
        
        # Log batch start
        self.log_batch_metadata(batch_id, 'started', 0)
        
        try:
            # Read CSV
            logger.info("Reading CSV file...")
            df = pd.read_csv(file_path)
            logger.info(f"Loaded {len(df)} records from CSV")
            
            # Validate data
            df_valid, validation_stats = self.validate_data(df)
            
            # Upload raw file to MinIO
            logger.info("Uploading to MinIO...")
            minio_path = self.upload_to_minio(file_path, batch_id)
            
            # Insert to PostgreSQL
            logger.info("Inserting to PostgreSQL...")
            records_inserted = self.insert_to_postgres(df_valid, batch_id)
            
            # Log successful completion
            self.log_batch_metadata(batch_id, 'completed', records_inserted)
            
            # Return statistics
            stats = {
                'batch_id': batch_id,
                'status': 'success',
                'file_path': file_path,
                'minio_path': minio_path,
                'records_read': len(df),
                'records_inserted': records_inserted,
                'validation_stats': validation_stats
            }
            
            logger.info(f"Ingestion completed successfully: {batch_id}")
            return stats
            
        except Exception as e:
            logger.error(f"Ingestion failed: {e}")
            self.log_batch_metadata(batch_id, 'failed', 0, str(e))
            raise


def main():
    """Main entry point for ingestion service"""
    if len(sys.argv) < 2:
        print("Usage: python ingestion_service.py <csv_file_path>")
        sys.exit(1)
    
    file_path = sys.argv[1]
    
    if not os.path.exists(file_path):
        logger.error(f"File not found: {file_path}")
        sys.exit(1)
    
    # Run ingestion
    service = DataIngestionService()
    stats = service.ingest_csv(file_path)
    
    # Print summary
    print("\n" + "="*50)
    print("INGESTION SUMMARY")
    print("="*50)
    print(f"Batch ID: {stats['batch_id']}")
    print(f"Status: {stats['status']}")
    print(f"Records Read: {stats['records_read']:,}")
    print(f"Records Inserted: {stats['records_inserted']:,}")
    print(f"Pass Rate: {stats['validation_stats']['pass_rate']:.2%}")
    print(f"MinIO Path: {stats['minio_path']}")
    print("="*50)


if __name__ == "__main__":
    main()
