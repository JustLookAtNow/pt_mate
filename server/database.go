package main

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/lib/pq"
)

func InitDB() (*sql.DB, error) {
	host := os.Getenv("DB_HOST")
	port := os.Getenv("DB_PORT")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	dbname := os.Getenv("DB_NAME")
	sslmode := os.Getenv("DB_SSLMODE")

	if host == "" {
		host = "localhost"
	}
	if port == "" {
		port = "5432"
	}
	if sslmode == "" {
		sslmode = "disable"
	}

	psqlInfo := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, dbname, sslmode)

	db, err := sql.Open("postgres", psqlInfo)
	if err != nil {
		return nil, err
	}

	if err = db.Ping(); err != nil {
		return nil, err
	}

	return db, nil
}

func RunMigrations(db *sql.DB) error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS app_versions (
			id SERIAL PRIMARY KEY,
			version VARCHAR(50) NOT NULL UNIQUE,
			release_notes TEXT,
			download_url VARCHAR(500),
			is_latest BOOLEAN DEFAULT FALSE,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		
		`CREATE TABLE IF NOT EXISTS app_statistics (
			id SERIAL PRIMARY KEY,
			device_id VARCHAR(100) NOT NULL,
			platform VARCHAR(50) NOT NULL,
			app_version VARCHAR(50) NOT NULL,
			first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			total_launches INTEGER DEFAULT 1,
			UNIQUE(device_id)
		)`,
		
		`CREATE INDEX IF NOT EXISTS idx_app_statistics_device_id ON app_statistics(device_id)`,
		`CREATE INDEX IF NOT EXISTS idx_app_statistics_platform ON app_statistics(platform)`,
		`CREATE INDEX IF NOT EXISTS idx_app_statistics_last_seen ON app_statistics(last_seen)`,
		`CREATE INDEX IF NOT EXISTS idx_app_versions_is_latest ON app_versions(is_latest)`,
	}

	for _, migration := range migrations {
		if _, err := db.Exec(migration); err != nil {
			return fmt.Errorf("failed to execute migration: %v", err)
		}
	}

	return nil
}