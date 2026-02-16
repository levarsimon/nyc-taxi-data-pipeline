-- Database initialization for NYC Taxi Data Pipeline
-- This script creates the necessary schemas and tables

-- Create airflow database for Airflow metadata
CREATE DATABASE airflow;

-- Connect to nyc_taxi database (main database)
\c nyc_taxi;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS processed;
CREATE SCHEMA IF NOT EXISTS aggregated;

-- Raw data table (stores ingested CSV data)
CREATE TABLE IF NOT EXISTS raw.trip_data (
    id VARCHAR(50) PRIMARY KEY,
    vendor_id INTEGER,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count INTEGER,
    pickup_longitude DOUBLE PRECISION,
    pickup_latitude DOUBLE PRECISION,
    dropoff_longitude DOUBLE PRECISION,
    dropoff_latitude DOUBLE PRECISION,
    store_and_fwd_flag VARCHAR(1),
    trip_duration INTEGER,
    ingestion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ingestion_batch_id VARCHAR(50)
);

-- Processed data table (cleaned and feature-engineered)
CREATE TABLE IF NOT EXISTS processed.trip_features (
    trip_id VARCHAR(50) PRIMARY KEY,
    vendor_id INTEGER,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count INTEGER,
    pickup_longitude DOUBLE PRECISION,
    pickup_latitude DOUBLE PRECISION,
    dropoff_longitude DOUBLE PRECISION,
    dropoff_latitude DOUBLE PRECISION,
    trip_duration INTEGER,
    
    -- Temporal features
    pickup_hour INTEGER,
    pickup_day_of_week INTEGER,
    pickup_day_of_month INTEGER,
    pickup_month INTEGER,
    pickup_year INTEGER,
    is_weekend BOOLEAN,
    is_rush_hour BOOLEAN,
    
    -- Distance features
    distance_km DOUBLE PRECISION,
    distance_manhattan DOUBLE PRECISION,
    
    -- Speed features
    avg_speed_kmh DOUBLE PRECISION,
    
    -- Processing metadata
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_batch_id VARCHAR(50),
    data_quality_score DOUBLE PRECISION
);

-- Aggregated data table (for ML model training)
CREATE TABLE IF NOT EXISTS aggregated.hourly_stats (
    stat_id SERIAL PRIMARY KEY,
    date_hour TIMESTAMP,
    vendor_id INTEGER,
    
    -- Aggregated metrics
    total_trips INTEGER,
    avg_trip_duration DOUBLE PRECISION,
    median_trip_duration DOUBLE PRECISION,
    avg_distance DOUBLE PRECISION,
    avg_speed DOUBLE PRECISION,
    avg_passenger_count DOUBLE PRECISION,
    
    -- Geographic patterns
    most_common_pickup_lat DOUBLE PRECISION,
    most_common_pickup_lon DOUBLE PRECISION,
    
    -- Time-based metrics
    rush_hour_percentage DOUBLE PRECISION,
    weekend_percentage DOUBLE PRECISION,
    
    -- Aggregation metadata
    aggregation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    aggregation_batch_id VARCHAR(50),
    
    UNIQUE(date_hour, vendor_id)
);

-- Daily aggregations for ML features
CREATE TABLE IF NOT EXISTS aggregated.daily_stats (
    stat_id SERIAL PRIMARY KEY,
    date DATE,
    vendor_id INTEGER,
    
    total_trips INTEGER,
    avg_trip_duration DOUBLE PRECISION,
    total_distance DOUBLE PRECISION,
    avg_speed DOUBLE PRECISION,
    peak_hour INTEGER,
    
    aggregation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(date, vendor_id)
);

-- Data quality tracking
CREATE TABLE IF NOT EXISTS processed.data_quality_log (
    log_id SERIAL PRIMARY KEY,
    batch_id VARCHAR(50),
    check_name VARCHAR(100),
    check_status VARCHAR(20),
    records_checked INTEGER,
    records_passed INTEGER,
    records_failed INTEGER,
    error_details TEXT,
    check_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Batch processing tracking
CREATE TABLE IF NOT EXISTS processed.batch_metadata (
    batch_id VARCHAR(50) PRIMARY KEY,
    batch_type VARCHAR(20), -- 'ingestion' or 'processing'
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    status VARCHAR(20), -- 'running', 'completed', 'failed'
    records_processed INTEGER,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_raw_pickup_datetime ON raw.trip_data(pickup_datetime);
CREATE INDEX IF NOT EXISTS idx_raw_batch_id ON raw.trip_data(ingestion_batch_id);

CREATE INDEX IF NOT EXISTS idx_processed_pickup_datetime ON processed.trip_features(pickup_datetime);
CREATE INDEX IF NOT EXISTS idx_processed_batch_id ON processed.trip_features(processing_batch_id);
CREATE INDEX IF NOT EXISTS idx_processed_hour ON processed.trip_features(pickup_hour);
CREATE INDEX IF NOT EXISTS idx_processed_dow ON processed.trip_features(pickup_day_of_week);

CREATE INDEX IF NOT EXISTS idx_hourly_stats_date ON aggregated.hourly_stats(date_hour);
CREATE INDEX IF NOT EXISTS idx_daily_stats_date ON aggregated.daily_stats(date);

-- Create views for easy querying
CREATE OR REPLACE VIEW processed.latest_processed_data AS
SELECT * FROM processed.trip_features
WHERE processing_batch_id = (
    SELECT batch_id FROM processed.batch_metadata 
    WHERE batch_type = 'processing' AND status = 'completed'
    ORDER BY end_time DESC LIMIT 1
);

CREATE OR REPLACE VIEW aggregated.latest_hourly_stats AS
SELECT * FROM aggregated.hourly_stats
WHERE aggregation_batch_id = (
    SELECT batch_id FROM processed.batch_metadata 
    WHERE batch_type = 'aggregation' AND status = 'completed'
    ORDER BY end_time DESC LIMIT 1
);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA raw TO taxiuser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA processed TO taxiuser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA aggregated TO taxiuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA raw TO taxiuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA processed TO taxiuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA aggregated TO taxiuser;

-- Insert initial batch metadata
INSERT INTO processed.batch_metadata (batch_id, batch_type, start_time, status) 
VALUES ('init', 'system', CURRENT_TIMESTAMP, 'completed')
ON CONFLICT DO NOTHING;
