#!/bin/bash
# NYC Taxi Data Pipeline - Setup Script

set -e

echo "=========================================="
echo "NYC Taxi Data Pipeline Setup"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check Docker
echo "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

echo -e "${GREEN}✓ Docker and Docker Compose found${NC}"

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

echo -e "${GREEN}✓ Docker daemon is running${NC}"

# Create necessary directories
echo ""
echo "Creating directory structure..."
mkdir -p data/raw data/processed
mkdir -p airflow/dags airflow/logs airflow/plugins
mkdir -p microservices/ingestion microservices/processing microservices/delivery microservices/storage
mkdir -p configs scripts docs

echo -e "${GREEN}✓ Directories created${NC}"

# Create placeholder files
touch data/raw/.gitkeep
touch data/processed/.gitkeep
touch airflow/logs/.gitkeep

# Check for NYC Taxi dataset
echo ""
echo "Checking for NYC Taxi dataset..."
if [ ! -f "data/raw/train.csv" ]; then
    echo -e "${YELLOW}Warning: train.csv not found in data/raw/${NC}"
    echo ""
    echo "Please download the NYC Taxi Trip Duration dataset:"
    echo "1. Go to: https://www.kaggle.com/c/nyc-taxi-trip-duration/data"
    echo "2. Download train.csv"
    echo "3. Place it in: data/raw/train.csv"
    echo ""
    echo "Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Please download the dataset and run setup again."
        exit 0
    fi
else
    echo -e "${GREEN}✓ Dataset found${NC}"
    FILE_SIZE=$(ls -lh data/raw/train.csv | awk '{print $5}')
    echo "  File size: $FILE_SIZE"
fi

# Check .env file
echo ""
echo "Checking environment configuration..."
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Warning: .env file not found, it should have been created${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Environment file found${NC}"

# Pull Docker images
echo ""
echo "Pulling Docker images (this may take a while)..."
docker-compose pull

echo -e "${GREEN}✓ Docker images pulled${NC}"

# Build custom images
echo ""
echo "Building custom Docker images..."
docker-compose build

echo -e "${GREEN}✓ Custom images built${NC}"

# Start services
echo ""
echo "Starting services..."
docker-compose up -d

echo -e "${GREEN}✓ Services starting...${NC}"

# Wait for services to be ready
echo ""
echo "Waiting for services to initialize (this may take 2-3 minutes)..."
sleep 30

# Check service health
echo ""
echo "Checking service health..."

# Check PostgreSQL
echo -n "  PostgreSQL: "
if docker-compose exec -T postgres pg_isready -U taxiuser &> /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check MinIO
echo -n "  MinIO: "
if curl -sf http://localhost:9000/minio/health/live &> /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}⚠ Not ready yet${NC}"
fi

# Check Airflow
echo -n "  Airflow: "
if curl -sf http://localhost:8080/health &> /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}⚠ Not ready yet (may take another minute)${NC}"
fi

# Check API
echo -n "  Data API: "
if curl -sf http://localhost:8000/health &> /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}⚠ Not ready yet${NC}"
fi

# Print access information
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Service Access Information:"
echo "  Airflow UI:    http://localhost:8080"
echo "    Username:    admin"
echo "    Password:    admin"
echo ""
echo "  MinIO Console: http://localhost:9001"
echo "    Username:    minioadmin"
echo "    Password:    minioadmin"
echo ""
echo "  Spark Master:  http://localhost:8081"
echo ""
echo "  Data API:      http://localhost:8000"
echo "  API Docs:      http://localhost:8000/docs"
echo "    API Key:     your-secret-api-key"
echo ""
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Wait ~2 minutes for all services to fully start"
echo "2. Access Airflow UI at http://localhost:8080"
echo "3. Enable and trigger 'monthly_ingestion' DAG"
echo "4. After ingestion completes, trigger 'quarterly_processing' DAG"
echo "5. Query data via API at http://localhost:8000/docs"
echo ""
echo "For detailed instructions, see SETUP_GUIDE.md"
echo ""
echo "To view logs: docker-compose logs -f [service_name]"
echo "To stop: docker-compose down"
echo "To restart: docker-compose restart"
echo "=========================================="
