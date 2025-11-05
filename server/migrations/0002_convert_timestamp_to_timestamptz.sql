-- +goose Up
-- Convert existing TIMESTAMP columns (if any) to TIMESTAMPTZ in UTC
-- This is safe to run multiple times; ALTER TYPE only applies when current type is TIMESTAMP

-- app_versions timestamps
-- +goose StatementBegin
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='app_versions' AND column_name='created_at' AND data_type='timestamp without time zone'
    ) THEN
        ALTER TABLE app_versions ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';
    END IF;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='app_versions' AND column_name='updated_at' AND data_type='timestamp without time zone'
    ) THEN
        ALTER TABLE app_versions ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';
    END IF;
END $$;
-- +goose StatementEnd

-- app_statistics timestamps
-- +goose StatementBegin
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='app_statistics' AND column_name='first_seen' AND data_type='timestamp without time zone'
    ) THEN
        ALTER TABLE app_statistics ALTER COLUMN first_seen TYPE TIMESTAMPTZ USING first_seen AT TIME ZONE 'UTC';
    END IF;
END $$;
-- +goose StatementEnd

-- +goose StatementBegin
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='app_statistics' AND column_name='last_seen' AND data_type='timestamp without time zone'
    ) THEN
        ALTER TABLE app_statistics ALTER COLUMN last_seen TYPE TIMESTAMPTZ USING last_seen AT TIME ZONE 'UTC';
    END IF;
END $$;
-- +goose StatementEnd

-- +goose Down
-- No-op: do not convert back to TIMESTAMP