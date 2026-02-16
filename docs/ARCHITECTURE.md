# Architecture Diagram

This project uses a microservices-based batch processing architecture.

## Visual Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCE LAYER                            │
│                    NYC Taxi Trip Duration Dataset                    │
│                         (Kaggle - 1.4M+ records)                     │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ CSV Files
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│                    ORCHESTRATION LAYER                               │
│                      Apache Airflow 2.7.0                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  ┌─────────────────────┐    ┌──────────────────────────┐    │  │
│  │  │ Monthly Ingestion   │    │ Quarterly Processing     │    │  │
│  │  │      DAG            │    │        DAG               │    │  │
│  │  │  Schedule: 0 0 1 * *│    │  Schedule: 0 0 1 */3 *   │    │  │
│  │  └─────────────────────┘    └──────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────┬─────────────────────┬────────────────────────┬───────────────┘
      │                     │                        │
      │ Triggers            │ Triggers               │ Monitors
      │                     │                        │
      ▼                     ▼                        ▼
┌──────────────┐    ┌──────────────┐        ┌──────────────┐
│  INGESTION   │    │  PROCESSING  │        │   DELIVERY   │
│   SERVICE    │    │   SERVICE    │        │   SERVICE    │
│              │    │              │        │              │
│  Python 3.10 │    │ Apache Spark │        │  FastAPI     │
│  + Pandas    │    │    3.4.0     │        │   0.104      │
│  + MinIO SDK │    │  + PySpark   │        │              │
│              │    │              │        │  REST API    │
│ Microservice │    │ Microservice │        │ Microservice │
└──────┬───────┘    └──────┬───────┘        └──────┬───────┘
       │                   │                        │
       │ Writes Raw        │ Reads/Writes          │ Reads
       │                   │                        │
       ▼                   ▼                        ▼
┌──────────────────────────────────────────────────────────────┐
│                     STORAGE LAYER                             │
│  ┌─────────────────────┐         ┌──────────────────────┐   │
│  │   MinIO (S3)        │         │   PostgreSQL 15      │   │
│  │  Object Storage     │         │  Relational Database │   │
│  │                     │         │                      │   │
│  │ Buckets:            │         │ Schemas:             │   │
│  │  - raw-data         │────────▶│  - raw               │   │
│  │  - processed-data   │  Sync   │  - processed         │   │
│  │  - models           │         │  - aggregated        │   │
│  │                     │         │                      │   │
│  │ Features:           │         │ Tables:              │   │
│  │  - Versioning       │         │  - trip_data         │   │
│  │  - Lifecycle mgmt   │         │  - trip_features     │   │
│  │  - Replication      │         │  - hourly_stats      │   │
│  │                     │         │  - daily_stats       │   │
│  └─────────────────────┘         │  - batch_metadata    │   │
│                                   └──────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
                                   │
                                   │ Query via API
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│                    CONSUMER LAYER                             │
│                                                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  ML Training    │  │  BI Dashboards  │  │  Analytics  │ │
│  │  Applications   │  │                 │  │  Tools      │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Data Ingestion Service
- **Language**: Python 3.10
- **Key Libraries**: Pandas, psycopg2, MinIO SDK
- **Responsibilities**:
  - Read CSV files in chunks
  - Validate data quality (nulls, ranges, duplicates)
  - Upload raw files to MinIO
  - Insert structured data to PostgreSQL
  - Track batch metadata
- **Reliability**: Retry logic, transaction management
- **Scalability**: Chunked processing for large files

### 2. Data Processing Service
- **Framework**: Apache Spark 3.4.0
- **Key Libraries**: PySpark SQL
- **Responsibilities**:
  - Feature engineering (temporal, distance, speed)
  - Data cleaning and quality scoring
  - Hourly and daily aggregations
  - Statistical computations
- **Reliability**: Fault-tolerant execution
- **Scalability**: Distributed processing, master-worker architecture

### 3. Data Delivery Service
- **Framework**: FastAPI
- **Responsibilities**:
  - RESTful API for data access
  - Authentication via API keys
  - Pagination and filtering
  - Data serialization
- **Reliability**: Connection pooling, error handling
- **Scalability**: Async endpoints, stateless design

### 4. Storage Layer
**MinIO (Object Storage)**:
- Raw CSV files (immutable)
- Versioning enabled
- Lifecycle policies
- 3-bucket strategy

**PostgreSQL (Relational DB)**:
- 3-schema design (raw, processed, aggregated)
- Indexed for query performance
- ACID compliance
- Point-in-time recovery

### 5. Orchestration
**Apache Airflow**:
- DAG-based workflows
- Scheduled execution
- Dependency management
- Retry and alerting
- Web UI for monitoring

## Data Flow

### Ingestion Flow (Monthly)
```
CSV File → Validation → MinIO Upload → PostgreSQL Insert → Metadata Logging
```

### Processing Flow (Quarterly)
```
Raw Data → Feature Engineering → Quality Scoring → 
Processed Storage → Aggregation → Statistics Storage
```

### Delivery Flow (On-Demand)
```
API Request → Authentication → Query Building → 
Data Fetch → Serialization → JSON Response
```

## Network Architecture

All services run in isolated Docker network `taxi-network`:
- Inter-service communication via service names
- No external exposure except designated ports
- Health checks for all critical services

## Security Model

### Authentication & Authorization
- API key-based authentication
- PostgreSQL role-based access control
- MinIO access key management

### Data Protection
- Environment variables for secrets
- No credentials in code
- Encrypted connections (production)

### Network Security
- Docker network isolation
- Firewall rules (production)
- VPC deployment (cloud)

## Scalability Strategy

### Horizontal Scaling
- Spark workers can be added dynamically
- API instances behind load balancer
- Database read replicas

### Vertical Scaling
- Adjust container resources in docker-compose.yml
- Database connection pooling
- Spark executor memory configuration

### Data Partitioning
- Time-based partitioning in PostgreSQL
- Bucket organization in MinIO
- Spark shuffle partitions

## Monitoring Points

1. **Pipeline Health**: Airflow UI
2. **Processing Performance**: Spark UI
3. **Storage Usage**: MinIO Console
4. **Database Queries**: PostgreSQL logs
5. **API Performance**: FastAPI metrics
6. **System Resources**: Docker stats

## Technology Decisions Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Orchestration | Apache Airflow | Industry standard, Python-native |
| Processing | Apache Spark | Distributed computing, large datasets |
| Storage (Object) | MinIO | S3-compatible, self-hosted |
| Storage (DB) | PostgreSQL | ACID, complex queries, open-source |
| API | FastAPI | Modern, async, auto-documentation |
| Containerization | Docker | Reproducibility, portability |
| Infrastructure | Docker Compose | Local development, IaC |

## Future Enhancements

1. **Streaming**: Add Kafka for real-time ingestion
2. **Monitoring**: Prometheus + Grafana
3. **CI/CD**: GitHub Actions pipeline
4. **Cloud**: Kubernetes deployment
5. **ML Ops**: MLflow integration
6. **Data Quality**: Great Expectations framework
7. **Catalog**: Apache Atlas metadata management
8. **Security**: HashiCorp Vault for secrets
