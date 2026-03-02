package main

import (
	_ "embed"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

// Embed static admin pages so they are available regardless of working directory
//go:embed admin/static/index.html
var adminIndexHTML []byte

//go:embed admin/static/login.html
var adminLoginHTML []byte

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

    // Configure timezone for analytics (UTC+8)
    // This doesn't change DB timezone; it's for reference if needed
    _ = time.FixedZone("UTC+8", 8*3600)

    r.GET("/health", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "ok"})
    })

    // Routes
    r.POST("/api/v1/check-update", appSvc.CheckUpdate)
    r.POST("/api/v1/github/version-update", verSvc.UpdateVersion)

    // Admin routes: login and protected group
    r.POST("/api/v1/admin/login", AdminLoginHandler)
    admin := r.Group("/api/v1/admin")
    admin.Use(AdminAuthMiddleware())
    {
        admin.GET("/stats/overview", AdminStatsOverview(db))
        admin.GET("/stats/platforms", AdminStatsPlatforms(db))
        admin.GET("/stats/versions", AdminStatsVersions(db))
        admin.GET("/stats/devices", AdminStatsDevices(db))
        admin.GET("/stats/trend/dau", AdminStatsTrendDAU(db))

        // Version management
        admin.GET("/versions", verSvc.AdminListVersions)
        admin.POST("/versions/:id", verSvc.AdminUpdateVersion)
        admin.DELETE("/versions/:id", verSvc.AdminDeleteVersion)
    }

    // Root redirect: always to /admin; the page checks token (localStorage)
    r.GET("/", func(c *gin.Context) {
        c.Redirect(http.StatusFound, "/admin")
    })

    // Serve static admin pages from embedded resources
    r.GET("/admin", func(c *gin.Context) {
        c.Data(http.StatusOK, "text/html; charset=utf-8", adminIndexHTML)
    })
    r.GET("/admin/login", func(c *gin.Context) {
        c.Data(http.StatusOK, "text/html; charset=utf-8", adminLoginHTML)
    })

    addr := os.Getenv("SERVER_ADDR")
    if addr == "" {
        addr = ":8080"
    }
    if err := r.Run(addr); err != nil {
        log.Fatalf("server run failed: %v", err)
    }
}
