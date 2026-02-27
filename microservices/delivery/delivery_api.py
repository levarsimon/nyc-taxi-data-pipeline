"""
NYC Taxi Data Delivery API

This service provides RESTful API endpoints to deliver processed data
to ML applications and other consumers.
"""

from fastapi import FastAPI, HTTPException, Depends, Query, Header
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from typing import List, Optional
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime, date
import os
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="NYC Taxi Data API",
    description="API for accessing processed NYC Taxi trip data",
    version="1.0.0"
)

# Configuration
POSTGRES_CONFIG = {
    'host': os.getenv('POSTGRES_HOST', 'localhost'),
    'port': os.getenv('POSTGRES_PORT', '5432'),
    'user': os.getenv('POSTGRES_USER', 'taxiuser'),
    'password': os.getenv('POSTGRES_PASSWORD', 'taxipass'),
    'database': os.getenv('POSTGRES_DB', 'nyc_taxi')
}

API_KEY = os.getenv('API_KEY', 'the-secret-api-key')


# Pydantic models
class TripFeature(BaseModel):
    """Processed trip feature model"""
    trip_id: str
    vendor_id: int
    pickup_datetime: datetime
    dropoff_datetime: datetime
    passenger_count: int
    pickup_longitude: float
    pickup_latitude: float
    dropoff_longitude: float
    dropoff_latitude: float
    trip_duration: int
    pickup_hour: int
    pickup_day_of_week: int
    is_weekend: bool
    is_rush_hour: bool
    distance_km: float
    avg_speed_kmh: float
    data_quality_score: float


class HourlyStat(BaseModel):
    """Hourly aggregation model"""
    date_hour: datetime
    vendor_id: int
    total_trips: int
    avg_trip_duration: float
    median_trip_duration: float
    avg_distance: float
    avg_speed: float
    avg_passenger_count: float
    rush_hour_percentage: float


class DailyStat(BaseModel):
    """Daily aggregation model"""
    date: date
    vendor_id: int
    total_trips: int
    avg_trip_duration: float
    total_distance: float
    avg_speed: float
    peak_hour: Optional[int]


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    timestamp: datetime
    database: str


class StatsResponse(BaseModel):
    """Statistics response"""
    total_raw_records: int
    total_processed_records: int
    latest_batch: Optional[str]
    data_quality_avg: Optional[float]


# Database connection
def get_db():
    """Create database connection"""
    try:
        conn = psycopg2.connect(**POSTGRES_CONFIG, cursor_factory=RealDictCursor)
        yield conn
        conn.close()
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise HTTPException(status_code=500, detail="Database connection failed")


# Authentication
def verify_api_key(x_api_key: str = Header(...)):
    """Verify API key"""
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return x_api_key


# Endpoints
@app.get("/", tags=["General"])
async def root():
    """Root endpoint"""
    return {
        "message": "NYC Taxi Data API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "stats": "/stats",
            "trips": "/trips",
            "hourly": "/aggregated/hourly",
            "daily": "/aggregated/daily"
        }
    }


@app.get("/health", response_model=HealthResponse, tags=["General"])
async def health_check(conn=Depends(get_db)):
    """Health check endpoint"""
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        db_status = "connected"
    except:
        db_status = "disconnected"
    finally:
        cursor.close()
    
    return HealthResponse(
        status="healthy" if db_status == "connected" else "unhealthy",
        timestamp=datetime.now(),
        database=db_status
    )


@app.get("/stats", response_model=StatsResponse, tags=["General"])
async def get_statistics(
    conn=Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get overall statistics"""
    cursor = conn.cursor()
    
    try:
        # Count raw records
        cursor.execute("SELECT COUNT(*) as count FROM raw.trip_data")
        total_raw = cursor.fetchone()['count']
        
        # Count processed records
        cursor.execute("SELECT COUNT(*) as count FROM processed.trip_features")
        total_processed = cursor.fetchone()['count']
        
        # Get latest batch
        cursor.execute("""
            SELECT batch_id FROM processed.batch_metadata 
            WHERE status = 'completed' 
            ORDER BY end_time DESC LIMIT 1
        """)
        latest = cursor.fetchone()
        latest_batch = latest['batch_id'] if latest else None
        
        # Average data quality
        cursor.execute("SELECT AVG(data_quality_score) as avg_quality FROM processed.trip_features")
        quality = cursor.fetchone()
        avg_quality = float(quality['avg_quality']) if quality['avg_quality'] else None
        
        return StatsResponse(
            total_raw_records=total_raw,
            total_processed_records=total_processed,
            latest_batch=latest_batch,
            data_quality_avg=avg_quality
        )
    finally:
        cursor.close()


@app.get("/trips", response_model=List[TripFeature], tags=["Data"])
async def get_trips(
    limit: int = Query(100, ge=1, le=10000, description="Number of records to return"),
    offset: int = Query(0, ge=0, description="Number of records to skip"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    vendor_id: Optional[int] = Query(None, description="Filter by vendor ID"),
    min_quality: Optional[float] = Query(None, ge=0, le=1, description="Minimum data quality score"),
    conn=Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get processed trip features with optional filters"""
    cursor = conn.cursor()
    
    try:
        # Build query
        query = "SELECT * FROM processed.trip_features WHERE 1=1"
        params = []
        
        if start_date:
            query += " AND pickup_datetime >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND pickup_datetime <= %s"
            params.append(end_date)
        
        if vendor_id is not None:
            query += " AND vendor_id = %s"
            params.append(vendor_id)
        
        if min_quality is not None:
            query += " AND data_quality_score >= %s"
            params.append(min_quality)
        
        query += " ORDER BY pickup_datetime DESC LIMIT %s OFFSET %s"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        
        return [TripFeature(**row) for row in results]
    finally:
        cursor.close()


@app.get("/aggregated/hourly", response_model=List[HourlyStat], tags=["Aggregations"])
async def get_hourly_stats(
    limit: int = Query(100, ge=1, le=10000),
    offset: int = Query(0, ge=0),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    vendor_id: Optional[int] = Query(None),
    conn=Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get hourly aggregated statistics"""
    cursor = conn.cursor()
    
    try:
        query = "SELECT * FROM aggregated.hourly_stats WHERE 1=1"
        params = []
        
        if start_date:
            query += " AND date_hour >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND date_hour <= %s"
            params.append(end_date)
        
        if vendor_id is not None:
            query += " AND vendor_id = %s"
            params.append(vendor_id)
        
        query += " ORDER BY date_hour DESC LIMIT %s OFFSET %s"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        
        return [HourlyStat(**row) for row in results]
    finally:
        cursor.close()


@app.get("/aggregated/daily", response_model=List[DailyStat], tags=["Aggregations"])
async def get_daily_stats(
    limit: int = Query(100, ge=1, le=10000),
    offset: int = Query(0, ge=0),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    vendor_id: Optional[int] = Query(None),
    conn=Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get daily aggregated statistics"""
    cursor = conn.cursor()
    
    try:
        query = "SELECT * FROM aggregated.daily_stats WHERE 1=1"
        params = []
        
        if start_date:
            query += " AND date >= %s"
            params.append(start_date)
        
        if end_date:
            query += " AND date <= %s"
            params.append(end_date)
        
        if vendor_id is not None:
            query += " AND vendor_id = %s"
            params.append(vendor_id)
        
        query += " ORDER BY date DESC LIMIT %s OFFSET %s"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        
        return [DailyStat(**row) for row in results]
    finally:
        cursor.close()


@app.get("/batches", tags=["Metadata"])
async def get_batches(
    limit: int = Query(20, ge=1, le=100),
    conn=Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get batch processing metadata"""
    cursor = conn.cursor()
    
    try:
        cursor.execute("""
            SELECT batch_id, batch_type, start_time, end_time, 
                   status, records_processed, error_message
            FROM processed.batch_metadata
            ORDER BY start_time DESC
            LIMIT %s
        """, (limit,))
        
        results = cursor.fetchall()
        return {"batches": results}
    finally:
        cursor.close()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
