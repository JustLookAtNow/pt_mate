package main

import (
    "log"
    "net/http"
    "os"

    "github.com/gin-gonic/gin"
    "github.com/joho/godotenv"
)

// load .env files using godotenv; ignore missing files
func loadDotEnv(paths ...string) {
    for _, p := range paths {
        _ = godotenv.Load(p)
    }
}

func main() {
    // Load environment variables from .env files (server/.env and root .env)
    loadDotEnv("server/.env", ".env")

    // Run migrations first to ensure schema is up-to-date
    if err := RunMigrations(); err != nil {
        log.Fatalf("migrations failed: %v", err)
    }

    // Init ORM
    db, err := InitDB()
    if err != nil {
        log.Fatalf("init db failed: %v", err)
    }

    // Wire services
    appSvc := NewAppService(db)
    verSvc := NewVersionService(db)

    // Setup router
    r := gin.Default()

    r.GET("/health", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "ok"})
    })

    // Routes
    r.POST("/api/check_update", appSvc.CheckUpdate)
    r.POST("/api/version/update", verSvc.UpdateVersion)

    addr := os.Getenv("SERVER_ADDR")
    if addr == "" {
        addr = ":8080"
    }
    if err := r.Run(addr); err != nil {
        log.Fatalf("server run failed: %v", err)
    }
}
