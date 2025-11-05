package main

import (
    "flag"
    "fmt"
    "log"
    "os"
    "strconv"

    "github.com/joho/godotenv"
    goose "github.com/pressly/goose/v3"
    migfs "server/migrations"
)

// load .env files using godotenv; ignore missing files
func loadDotEnv(paths ...string) {
    for _, p := range paths {
        _ = godotenv.Load(p)
    }
}

func main() {
    // Load env so CLI can use DB_* variables when DATABASE_URL is not set
    loadDotEnv("server/.env", ".env")

    // Database DSN via env for flexibility. Same format used in database.go
    dsn := os.Getenv("DATABASE_URL")
    if dsn == "" {
        // Build DSN from DB_* variables
        host := os.Getenv("DB_HOST")
        port := os.Getenv("DB_PORT")
        user := os.Getenv("DB_USER")
        password := os.Getenv("DB_PASSWORD")
        dbname := os.Getenv("DB_NAME")
        sslmode := os.Getenv("DB_SSLMODE")
        if sslmode == "" {
            sslmode = "disable"
        }
        if user == "" || dbname == "" {
            log.Fatal("missing DB_USER or DB_NAME; provide DATABASE_URL or set DB_* envs")
        }
        dsn = fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s", user, password, host, port, dbname, sslmode)
    }

	// Set goose dialect
	if err := goose.SetDialect("postgres"); err != nil {
		log.Fatalf("goose SetDialect: %v", err)
	}

	// Parse command
	flag.Parse()
	args := flag.Args()
	if len(args) < 1 {
		fmt.Println("migrate requires a command: status|up|down|redo|reset|up-to|down-to")
		os.Exit(1)
	}
	cmd := args[0]

    // Open DB
    db, err := goose.OpenDBWithDriver("postgres", dsn)
    if err != nil {
        log.Fatalf("goose OpenDB: %v", err)
    }
    defer db.Close()

    // Use embedded FS (go:embed provides an io/fs)
    goose.SetBaseFS(migfs.FS)
    migrationsDir := "."

	switch cmd {
	case "status":
		if err := goose.Status(db, migrationsDir); err != nil {
			log.Fatalf("goose status: %v", err)
		}
	case "up":
		if err := goose.Up(db, migrationsDir); err != nil {
			log.Fatalf("goose up: %v", err)
		}
	case "down":
		if err := goose.Down(db, migrationsDir); err != nil {
			log.Fatalf("goose down: %v", err)
		}
	case "redo":
		if err := goose.Redo(db, migrationsDir); err != nil {
			log.Fatalf("goose redo: %v", err)
		}
	case "reset":
		if err := goose.Reset(db, migrationsDir); err != nil {
			log.Fatalf("goose reset: %v", err)
		}
	case "up-to":
		if len(args) < 2 {
			log.Fatal("up-to requires a version")
		}
        version, err := strconv.ParseInt(args[1], 10, 64)
        if err != nil {
            log.Fatalf("invalid version: %v", err)
        }
        if err := goose.UpTo(db, migrationsDir, version); err != nil {
            log.Fatalf("goose up-to: %v", err)
        }
	case "down-to":
		if len(args) < 2 {
			log.Fatal("down-to requires a version")
		}
        version, err := strconv.ParseInt(args[1], 10, 64)
        if err != nil {
            log.Fatalf("invalid version: %v", err)
        }
        if err := goose.DownTo(db, migrationsDir, version); err != nil {
            log.Fatalf("goose down-to: %v", err)
        }
	default:
		log.Fatalf("unknown command: %s", cmd)
	}
}
