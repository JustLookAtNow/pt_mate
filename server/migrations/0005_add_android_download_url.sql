-- +goose Up
-- SQL in this section is executed when the migration is applied.
ALTER TABLE app_versions ADD COLUMN android_download_url VARCHAR(500);

-- +goose Down
-- SQL in this section is executed when the migration is rolled back.
ALTER TABLE app_versions DROP COLUMN android_download_url;
