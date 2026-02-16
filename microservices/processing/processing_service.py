"""
NYC Taxi Data Processing Service using Apache Spark

This service handles data processing, feature engineering, and aggregation
for ML model training.
"""

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from pyspark.sql.types import *
from datetime import datetime
import sys
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class TaxiDataProcessor:
    """Process NYC Taxi data with Spark"""
    
    def __init__(self, postgres_host='postgres', postgres_port='5432',
                 postgres_db='nyc_taxi', postgres_user='taxiuser',
                 postgres_password='taxipass'):
        """Initialize Spark session"""
        
        self.postgres_url = f"jdbc:postgresql://{postgres_host}:{postgres_port}/{postgres_db}"
        self.postgres_properties = {
            "user": postgres_user,
            "password": postgres_password,
            "driver": "org.postgresql.Driver"
        }
        
        # Create Spark session
        self.spark = SparkSession.builder \
            .appName("NYC Taxi Data Processing") \
            .config("spark.executor.memory", "2g") \
            .config("spark.driver.memory", "1g") \
            .getOrCreate()
        
        logger.info("Spark session initialized")
    
    def read_raw_data(self, batch_id=None):
        """Read raw data from PostgreSQL"""
        query = "SELECT * FROM raw.trip_data"
        
        if batch_id:
            query += f" WHERE ingestion_batch_id = '{batch_id}'"
        
        df = self.spark.read \
            .jdbc(self.postgres_url, f"({query}) AS data", properties=self.postgres_properties)
        
        logger.info(f"Read {df.count()} records from raw.trip_data")
        return df
    
    def engineer_features(self, df):
        """
        Perform feature engineering
        
        Args:
            df: Spark DataFrame with raw trip data
            
        Returns:
            DataFrame with engineered features
        """
        logger.info("Starting feature engineering...")
        
        # Temporal features
        df = df.withColumn("pickup_hour", F.hour("pickup_datetime")) \
               .withColumn("pickup_day_of_week", F.dayofweek("pickup_datetime")) \
               .withColumn("pickup_day_of_month", F.dayofmonth("pickup_datetime")) \
               .withColumn("pickup_month", F.month("pickup_datetime")) \
               .withColumn("pickup_year", F.year("pickup_datetime"))
        
        # Weekend flag
        df = df.withColumn("is_weekend", 
                          F.when(F.col("pickup_day_of_week").isin([1, 7]), True).otherwise(False))
        
        # Rush hour flag (7-9 AM or 5-7 PM on weekdays)
        df = df.withColumn("is_rush_hour",
                          F.when(
                              (~F.col("is_weekend")) & 
                              ((F.col("pickup_hour").between(7, 9)) | 
                               (F.col("pickup_hour").between(17, 19))),
                              True
                          ).otherwise(False))
        
        # Calculate distances
        # Haversine distance (great circle distance)
        df = df.withColumn("lat_diff", F.radians("dropoff_latitude") - F.radians("pickup_latitude")) \
               .withColumn("lon_diff", F.radians("dropoff_longitude") - F.radians("pickup_longitude"))
        
        # Haversine formula
        df = df.withColumn("a", 
                          F.pow(F.sin(F.col("lat_diff") / 2), 2) +
                          F.cos(F.radians("pickup_latitude")) *
                          F.cos(F.radians("dropoff_latitude")) *
                          F.pow(F.sin(F.col("lon_diff") / 2), 2))
        
        df = df.withColumn("c", 2 * F.asin(F.sqrt(F.col("a"))))
        df = df.withColumn("distance_km", 6371 * F.col("c"))  # Earth radius = 6371 km
        
        # Manhattan distance (approximation)
        df = df.withColumn("distance_manhattan",
                          F.abs(F.col("dropoff_latitude") - F.col("pickup_latitude")) +
                          F.abs(F.col("dropoff_longitude") - F.col("pickup_longitude")))
        
        # Average speed (km/h)
        df = df.withColumn("avg_speed_kmh",
                          (F.col("distance_km") / (F.col("trip_duration") / 3600)))
        
        # Data quality score (simple heuristic)
        df = df.withColumn("data_quality_score",
                          F.when(
                              (F.col("distance_km") > 0) & 
                              (F.col("avg_speed_kmh") > 0) &
                              (F.col("avg_speed_kmh") < 120) &  # Reasonable speed limit
                              (F.col("trip_duration") > 60) &  # At least 1 minute
                              (F.col("trip_duration") < 7200),  # Less than 2 hours
                              1.0
                          ).otherwise(0.5))
        
        # Clean up intermediate columns
        df = df.drop("lat_diff", "lon_diff", "a", "c")
        
        # Rename id to trip_id for clarity
        df = df.withColumnRenamed("id", "trip_id")
        
        logger.info("Feature engineering complete")
        return df
    
    def write_processed_data(self, df, batch_id):
        """Write processed data to PostgreSQL"""
        
        # Add processing metadata
        df = df.withColumn("processing_timestamp", F.lit(datetime.now())) \
               .withColumn("processing_batch_id", F.lit(batch_id))
        
        # Select columns for processed table
        columns = [
            "trip_id", "vendor_id", "pickup_datetime", "dropoff_datetime",
            "passenger_count", "pickup_longitude", "pickup_latitude",
            "dropoff_longitude", "dropoff_latitude", "trip_duration",
            "pickup_hour", "pickup_day_of_week", "pickup_day_of_month",
            "pickup_month", "pickup_year", "is_weekend", "is_rush_hour",
            "distance_km", "distance_manhattan", "avg_speed_kmh",
            "processing_timestamp", "processing_batch_id", "data_quality_score"
        ]
        
        df_to_write = df.select(*columns)
        
        # Write to PostgreSQL
        df_to_write.write \
            .jdbc(self.postgres_url, "processed.trip_features",
                  mode="append", properties=self.postgres_properties)
        
        logger.info(f"Wrote {df_to_write.count()} records to processed.trip_features")
    
    def aggregate_hourly(self, df, batch_id):
        """Create hourly aggregations"""
        logger.info("Creating hourly aggregations...")
        
        # Truncate to hour
        df = df.withColumn("date_hour", F.date_trunc("hour", "pickup_datetime"))
        
        # Aggregate by hour and vendor
        agg_df = df.groupBy("date_hour", "vendor_id").agg(
            F.count("*").alias("total_trips"),
            F.avg("trip_duration").alias("avg_trip_duration"),
            F.expr("percentile_approx(trip_duration, 0.5)").alias("median_trip_duration"),
            F.avg("distance_km").alias("avg_distance"),
            F.avg("avg_speed_kmh").alias("avg_speed"),
            F.avg("passenger_count").alias("avg_passenger_count"),
            F.avg(F.when(F.col("is_rush_hour"), 1).otherwise(0)).alias("rush_hour_percentage"),
            F.avg(F.when(F.col("is_weekend"), 1).otherwise(0)).alias("weekend_percentage"),
            F.first("pickup_latitude").alias("most_common_pickup_lat"),
            F.first("pickup_longitude").alias("most_common_pickup_lon")
        )
        
        # Add metadata
        agg_df = agg_df.withColumn("aggregation_timestamp", F.lit(datetime.now())) \
                       .withColumn("aggregation_batch_id", F.lit(batch_id))
        
        # Write to PostgreSQL
        agg_df.write \
            .jdbc(self.postgres_url, "aggregated.hourly_stats",
                  mode="append", properties=self.postgres_properties)
        
        logger.info(f"Created {agg_df.count()} hourly aggregations")
        return agg_df
    
    def aggregate_daily(self, df, batch_id):
        """Create daily aggregations"""
        logger.info("Creating daily aggregations...")
        
        # Extract date
        df = df.withColumn("date", F.to_date("pickup_datetime"))
        
        # Find peak hour per day
        hourly_counts = df.groupBy("date", "vendor_id", "pickup_hour").count()
        window = Window.partitionBy("date", "vendor_id").orderBy(F.desc("count"))
        peak_hour_df = hourly_counts.withColumn("rank", F.row_number().over(window)) \
                                     .filter(F.col("rank") == 1) \
                                     .select("date", "vendor_id", 
                                            F.col("pickup_hour").alias("peak_hour"))
        
        # Daily aggregations
        daily_df = df.groupBy("date", "vendor_id").agg(
            F.count("*").alias("total_trips"),
            F.avg("trip_duration").alias("avg_trip_duration"),
            F.sum("distance_km").alias("total_distance"),
            F.avg("avg_speed_kmh").alias("avg_speed")
        )
        
        # Join with peak hour
        daily_df = daily_df.join(peak_hour_df, ["date", "vendor_id"], "left")
        
        # Add metadata
        daily_df = daily_df.withColumn("aggregation_timestamp", F.lit(datetime.now()))
        
        # Write to PostgreSQL
        daily_df.write \
            .jdbc(self.postgres_url, "aggregated.daily_stats",
                  mode="append", properties=self.postgres_properties)
        
        logger.info(f"Created {daily_df.count()} daily aggregations")
        return daily_df
    
    def run_processing_pipeline(self, batch_id=None):
        """
        Run complete processing pipeline
        
        Args:
            batch_id: Specific batch to process (optional, processes all if None)
        """
        processing_batch_id = f"proc_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        logger.info(f"Starting processing pipeline: {processing_batch_id}")
        
        try:
            # Read raw data
            df_raw = self.read_raw_data(batch_id)
            
            if df_raw.count() == 0:
                logger.warning("No data to process")
                return
            
            # Engineer features
            df_processed = self.engineer_features(df_raw)
            
            # Cache for multiple operations
            df_processed.cache()
            
            # Write processed data
            self.write_processed_data(df_processed, processing_batch_id)
            
            # Create aggregations
            self.aggregate_hourly(df_processed, processing_batch_id)
            self.aggregate_daily(df_processed, processing_batch_id)
            
            # Unpersist cached data
            df_processed.unpersist()
            
            logger.info(f"Processing pipeline completed: {processing_batch_id}")
            
        except Exception as e:
            logger.error(f"Processing pipeline failed: {e}")
            raise
        finally:
            self.spark.stop()


def main():
    """Main entry point"""
    batch_id = sys.argv[1] if len(sys.argv) > 1 else None
    
    processor = TaxiDataProcessor()
    processor.run_processing_pipeline(batch_id)


if __name__ == "__main__":
    main()
