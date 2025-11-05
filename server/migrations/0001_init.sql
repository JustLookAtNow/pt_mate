-- +goose Up
-- Initial schema: app_versions and app_statistics with TIMESTAMPTZ
CREATE TABLE IF NOT EXISTS app_versions (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) UNIQUE NOT NULL,
    release_notes TEXT,
    download_url VARCHAR(500),
    is_latest BOOLEAN DEFAULT FALSE,
    is_beta BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_versions_is_latest ON app_versions (is_latest);
CREATE INDEX IF NOT EXISTS idx_app_versions_is_beta ON app_versions (is_beta);

CREATE TABLE IF NOT EXISTS app_statistics (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(100) UNIQUE NOT NULL,
    platform VARCHAR(50) NOT NULL,
    app_version VARCHAR(50) NOT NULL,
    ip VARCHAR(64),
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    total_launches INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_app_statistics_last_seen ON app_statistics (last_seen);

-- +goose Down
DROP TABLE IF EXISTS app_statistics;
DROP TABLE IF EXISTS app_versions;