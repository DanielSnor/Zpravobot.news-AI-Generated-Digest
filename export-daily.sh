#!/bin/bash
DATE=$(date +%Y-%m-%d)
LOG="/app/data/logs/export.log"

mkdir -p /app/data/logs /app/data/archive

echo "[$(date)] Starting export..." >> "$LOG"

PGPASSWORD=${CLOUDRON_POSTGRESQL_PASSWORD} psql \
  -h ${CLOUDRON_POSTGRESQL_HOST} \
  -p ${CLOUDRON_POSTGRESQL_PORT} \
  -U ${CLOUDRON_POSTGRESQL_USERNAME} \
  -d ${CLOUDRON_POSTGRESQL_DATABASE} \
  -c "COPY (
    SELECT id, created_at, text, uri, url, account_id
    FROM statuses
    WHERE local = true 
      AND deleted_at IS NULL
      AND created_at > NOW() - INTERVAL '2 days'
    ORDER BY created_at DESC
  ) TO STDOUT WITH CSV HEADER" > /app/data/posts-latest.csv

cp /app/data/posts-latest.csv "/app/data/archive/posts-$DATE.csv"
find /app/data/archive -name "posts-*.csv" -mtime +7 -delete

LINES=$(wc -l < /app/data/posts-latest.csv)
echo "[$(date)] Exported $LINES posts" >> "$LOG"
