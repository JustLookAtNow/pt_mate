package main

import (
    "net/http"
    "strconv"
    "time"

    "github.com/gin-gonic/gin"
    "gorm.io/gorm"
)

// Helpers to parse window or custom range, using UTC+8 date boundaries
func parseRange(c *gin.Context) (from time.Time, to time.Time, err error) {
    loc := time.FixedZone("UTC+8", 8*3600)
    window := c.Query("window")
    if window == "" { window = "7d" }
    if window == "custom" {
        fromStr := c.Query("from")
        toStr := c.Query("to")
        if fromStr == "" || toStr == "" {
            return time.Time{}, time.Time{}, errBadRange
        }
        // Parse YYYY-MM-DD in UTC+8
        if from, err = time.ParseInLocation("2006-01-02", fromStr, loc); err != nil { return }
        if to, err = time.ParseInLocation("2006-01-02", toStr, loc); err != nil { return }
        // Inclusive range: to = local end of day
        to = to.Add(24 * time.Hour)
    } else {
        // Window 7d or 30d ending today (inclusive)
        days := 7
        if window == "30d" { days = 30 }
        now := time.Now().In(loc)
        endLocalMidnight := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, loc)
        start := endLocalMidnight.Add(time.Duration(-days) * 24 * time.Hour)
        from, to = start, endLocalMidnight
    }
    return
}

var errBadRange = gorm.ErrInvalidData

// GET /api/v1/admin/stats/overview
func AdminStatsOverview(db *gorm.DB) gin.HandlerFunc {
    return func(c *gin.Context) {
        from, to, err := parseRange(c)
        if err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "时间范围不合法"}); return }

        // DAU today (UTC+8)
        loc := time.FixedZone("UTC+8", 8*3600)
        now := time.Now().In(loc)
        today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
        var dauToday int64
        db.Raw("SELECT COUNT(DISTINCT device_id) FROM app_activity WHERE seen_date = (?::date)", today).Scan(&dauToday)

        // MAU 30d: distinct devices in last 30 days
        start30 := today.Add(-30 * 24 * time.Hour)
        var mau30d int64
        db.Raw("SELECT COUNT(DISTINCT device_id) FROM app_activity WHERE seen_date >= (?::date) AND seen_date < (?::date)", start30, today.Add(24*time.Hour)).Scan(&mau30d)

        // Total devices ever
        var totalDevices int64
        db.Raw("SELECT COUNT(*) FROM app_statistics").Scan(&totalDevices)

        // Devices in period (from-to)
        var periodDevices int64
        db.Raw("SELECT COUNT(DISTINCT device_id) FROM app_activity WHERE seen_date >= (?::date) AND seen_date < (?::date)", from, to).Scan(&periodDevices)

        c.JSON(http.StatusOK, gin.H{
            "dauToday": dauToday,
            "mau30d": mau30d,
            "totalDevices": totalDevices,
            "periodDevices": periodDevices,
        })
    }
}

// GET /api/v1/admin/stats/platforms
func AdminStatsPlatforms(db *gorm.DB) gin.HandlerFunc {
    type Row struct { Platform string `json:"platform"`; Count int64 `json:"count"` }
    return func(c *gin.Context) {
        var rows []Row
        // 设备维度统计：按当前平台分组（不限定时间窗口）
        db.Raw("SELECT s.platform AS platform, COUNT(*) AS count FROM app_statistics s GROUP BY s.platform ORDER BY count DESC").Scan(&rows)
        c.JSON(http.StatusOK, gin.H{"items": rows})
    }
}

// GET /api/v1/admin/stats/versions
func AdminStatsVersions(db *gorm.DB) gin.HandlerFunc {
    type Row struct { Version string `json:"version"`; Count int64 `json:"count"` }
    return func(c *gin.Context) {
        var rows []Row
        // 设备维度统计：按当前版本分组（不限定时间窗口）
        db.Raw("SELECT s.app_version AS version, COUNT(*) AS count FROM app_statistics s GROUP BY s.app_version ORDER BY count DESC").Scan(&rows)
        c.JSON(http.StatusOK, gin.H{"items": rows})
    }
}

// GET /api/v1/admin/stats/devices
func AdminStatsDevices(db *gorm.DB) gin.HandlerFunc {
    type Item struct {
        DeviceID      string    `json:"device_id"`
        Platform      string    `json:"platform"`
        AppVersion    string    `json:"app_version"`
        FirstSeen     time.Time `json:"first_seen"`
        LastSeen      time.Time `json:"last_seen"`
        TotalLaunches int       `json:"total_launches"`
        IP            string    `json:"ip"`
    }
    return func(c *gin.Context) {
        page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
        pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "20"))
        if pageSize <= 0 || pageSize > 200 { pageSize = 20 }
        offset := (page - 1) * pageSize

        platform := c.Query("platform")
        version := c.Query("version")
        q := c.Query("q")

        tx := db.Model(&AppStatistic{})
        if platform != "" { tx = tx.Where("platform = ?", platform) }
        if version != "" { tx = tx.Where("app_version = ?", version) }
        if q != "" { tx = tx.Where("device_id ILIKE ? OR ip ILIKE ?", "%"+q+"%", "%"+q+"%") }

        var total int64
        tx.Count(&total)

        var items []Item
        tx.Order("last_seen DESC").Limit(pageSize).Offset(offset).Scan(&items)

        c.JSON(http.StatusOK, gin.H{ "total": total, "items": items })
    }
}

// GET /api/v1/admin/stats/trend/dau
func AdminStatsTrendDAU(db *gorm.DB) gin.HandlerFunc {
    type Row struct { Date time.Time `json:"date"`; Count int64 `json:"count"` }
    return func(c *gin.Context) {
        from, to, err := parseRange(c)
        if err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "时间范围不合法"}); return }
        var rows []Row
        // Aggregate by seen_date (stored as date at UTC+8 local midnight)
        db.Raw("SELECT seen_date AS date, COUNT(DISTINCT device_id) AS count FROM app_activity WHERE seen_date >= (?::date) AND seen_date < (?::date) GROUP BY seen_date ORDER BY seen_date", from, to).Scan(&rows)
        var windowDevices int64
        db.Raw("SELECT COUNT(DISTINCT device_id) FROM app_activity WHERE seen_date >= (?::date) AND seen_date < (?::date)", from, to).Scan(&windowDevices)
        c.JSON(http.StatusOK, gin.H{"items": rows, "windowDevices": windowDevices})
    }
}