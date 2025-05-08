FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for ML libraries if any (e.g., for numpy, scipy)
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     build-essential \
#     && rm -rf /var/lib/apt/lists/*

COPY ./src/ml_engine/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY ./src/ml_engine /app/ml_engine

# Create directories for models and logs if scripts write to them directly
RUN mkdir -p /app/ml_engine/models \
    && mkdir -p /app/logs

# No CMD or ENTRYPOINT by default, as this container is run for specific tasks (train, predict)
# e.g., docker-compose run --rm ml_engine python ml_engine/train.py
