package main

import (
    "fmt"
    "log"
    "os"
    "time"

    goose "github.com/pressly/goose/v3"
    "gorm.io/driver/postgres"
    "gorm.io/gorm"

    migfs "server/migrations"
)

// InitDB creates a GORM DB connection using Postgres driver.
// It enforces session TimeZone=UTC for consistency with TIMESTAMPTZ storage.
func InitDB() (*gorm.DB, error) {
    host := os.Getenv("DB_HOST")
    port := os.Getenv("DB_PORT")
    user := os.Getenv("DB_USER")
    password := os.Getenv("DB_PASSWORD")
    dbname := os.Getenv("DB_NAME")
    sslmode := os.Getenv("DB_SSLMODE")
    if sslmode == "" {
        sslmode = "disable"
    }

    dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s TimeZone=UTC", host, port, user, password, dbname, sslmode)
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    if err != nil {
        return nil, err
    }

    sqlDB, err := db.DB()
    if err != nil {
        return nil, err
    }
    sqlDB.SetConnMaxLifetime(time.Minute * 3)
    sqlDB.SetMaxOpenConns(10)
    sqlDB.SetMaxIdleConns(10)

    return db, nil
}

// RunMigrations applies goose migrations using either DATABASE_URL or environment DSN.
func RunMigrations() error {
    dsn := os.Getenv("DATABASE_URL")
    if dsn == "" {
        host := os.Getenv("DB_HOST")
        port := os.Getenv("DB_PORT")
        user := os.Getenv("DB_USER")
        password := os.Getenv("DB_PASSWORD")
        dbname := os.Getenv("DB_NAME")
        sslmode := os.Getenv("DB_SSLMODE")
        if sslmode == "" {
            sslmode = "disable"
        }
        dsn = fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s", user, password, host, port, dbname, sslmode)
    }

    if err := goose.SetDialect("postgres"); err != nil {
        return err
    }
    // Use embedded migrations FS (io/fs)
    goose.SetBaseFS(migfs.FS)
    db, err := goose.OpenDBWithDriver("postgres", dsn)
    if err != nil {
        return err
    }
    defer db.Close()

    // With embedded migrations, use current directory "."
    if err := goose.Up(db, "."); err != nil {
        return err
    }
    log.Println("Migrations applied successfully")
    return nil
}