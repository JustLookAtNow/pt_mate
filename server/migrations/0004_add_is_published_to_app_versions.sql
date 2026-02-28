-- +goose Up
-- SQL in this section is executed when the migration is applied.
ALTER TABLE app_versions ADD COLUMN is_published BOOLEAN DEFAULT TRUE;

-- +goose Down
-- SQL in this section is executed when the migration is rolled back.
ALTER TABLE app_versions DROP COLUMN is_published;
