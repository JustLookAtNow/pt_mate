package main

import (
    "log"
    "net/http"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    "gorm.io/gorm"
)

type AppService struct {
    db *gorm.DB
}

func NewAppService(db *gorm.DB) *AppService {
    return &AppService{db: db}
}

func (s *AppService) CheckUpdate(c *gin.Context) {
    var req CheckUpdateRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Record client IP
    clientIP := c.ClientIP()

    // Process statistics and activity in background
    go func(deviceID, platform, appVersion, ip string) {
        defer func() {
            if r := recover(); r != nil {
                log.Printf("Recovered from panic in background analytics task: %v", r)
            }
        }()

        // Update or insert statistics
        if err := s.updateStatistics(deviceID, platform, appVersion, ip); err != nil {
            log.Printf("Failed to update statistics: %v", err)
            // Don't fail the request if statistics update fails
        }

        // Record daily activity for DAU trend (Asia/Shanghai UTC+8 day window)
        if err := s.recordDailyActivity(deviceID, platform, appVersion); err != nil {
            log.Printf("Failed to record daily activity: %v", err)
            // Do not fail the main request due to analytics logging
        }
    }(req.DeviceID, req.Platform, req.AppVersion, clientIP)

    // Get latest version according to beta opt-in
    latestVersion, err := s.getLatestVersion(req.IsBeta)
    if err != nil {
        log.Printf("Failed to get latest version: %v", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check for updates"})
        return
    }

	if latestVersion == nil {
		// No version information available
		c.JSON(http.StatusOK, CheckUpdateResponse{
			HasUpdate: false,
		})
		return
	}

	// Compare versions
	hasUpdate := s.compareVersions(req.AppVersion, latestVersion.Version)

	response := CheckUpdateResponse{
		HasUpdate: hasUpdate,
	}

    if hasUpdate {
        response.LatestVersion = latestVersion.Version
        response.ReleaseNotes = latestVersion.ReleaseNotes
        response.DownloadURL = latestVersion.DownloadURL
    }

	c.JSON(http.StatusOK, response)
}

func (s *AppService) updateStatistics(deviceID, platform, appVersion, ip string) error {
    var stat AppStatistic
    tx := s.db.Where("device_id = ?", deviceID).First(&stat)
    if tx.Error == nil && stat.ID != 0 {
        // Update existing
        stat.Platform = platform
        stat.AppVersion = appVersion
        stat.IP = ip
        stat.LastSeen = nowUTC()
        stat.TotalLaunches = stat.TotalLaunches + 1
        return s.db.Save(&stat).Error
    }
    if tx.Error != nil && tx.Error != gorm.ErrRecordNotFound {
        return tx.Error
    }
    // Create new
    newStat := AppStatistic{
        DeviceID:      deviceID,
        Platform:      platform,
        AppVersion:    appVersion,
        IP:            ip,
        FirstSeen:     nowUTC(),
        LastSeen:      nowUTC(),
        TotalLaunches: 1,
    }
    return s.db.Create(&newStat).Error
}

// recordDailyActivity inserts a record into app_activity for the current day (UTC+8),
// ensuring uniqueness per device per day.
func (s *AppService) recordDailyActivity(deviceID, platform, appVersion string) error {
    // Compute seen_date in UTC+8
    // Asia/Shanghai is UTC+8 without DST; we will derive date by adding +8h to UTC and truncating
    now := nowUTC()
    // Shift to UTC+8
    shifted := now.Add(8 * time.Hour)
    // Take date component (YYYY-MM-DD) by constructing time at midnight and then back to UTC midnight for storage
    y, m, d := shifted.Date()
    // Build time at local midnight (in UTC+8)
    localMidnight := time.Date(y, m, d, 0, 0, 0, 0, time.FixedZone("UTC+8", 8*3600))
    // Convert to date by taking the same Y-M-D but store as date type; GORM with type:date needs a time.Time
    seenDate := localMidnight

    // Insert with conflict ignore
    activity := AppActivity{
        DeviceID:   deviceID,
        Platform:   platform,
        AppVersion: appVersion,
        SeenDate:   seenDate,
        SeenAt:     now,
    }

    // Use ON CONFLICT DO NOTHING on (device_id, seen_date)
    // Explicitly cast seen_date to date type to avoid driver type mismatch
    sql := `INSERT INTO app_activity (device_id, platform, app_version, seen_date, seen_at)
            VALUES (?, ?, ?, (?::date), ?)
            ON CONFLICT (device_id, seen_date) DO NOTHING`
    return s.db.Exec(sql, activity.DeviceID, activity.Platform, activity.AppVersion, activity.SeenDate, activity.SeenAt).Error
}

func (s *AppService) getLatestVersion(includeBeta bool) (*AppVersion, error) {
    var version AppVersion
    q := s.db.Model(&AppVersion{}).Where("is_latest = ?", true)
    if !includeBeta {
        q = q.Where("is_beta = ?", false)
    }
    if err := q.Order("created_at DESC").Limit(1).First(&version).Error; err != nil {
        if err == gorm.ErrRecordNotFound {
            return nil, nil
        }
        return nil, err
    }
    return &version, nil
}

// Simple version comparison - assumes semantic versioning (x.y.z)
func (s *AppService) compareVersions(current, latest string) bool {
	// Remove 'v' prefix if present
	current = strings.TrimPrefix(current, "v")
	latest = strings.TrimPrefix(latest, "v")

	// Split versions into parts
	currentParts := strings.Split(current, ".")
	latestParts := strings.Split(latest, ".")

	// Ensure both have at least 3 parts
	for len(currentParts) < 3 {
		currentParts = append(currentParts, "0")
	}
	for len(latestParts) < 3 {
		latestParts = append(latestParts, "0")
	}

	// Compare each part
	for i := 0; i < 3; i++ {
		var currentNum, latestNum int

		// Parse numbers, ignore errors (default to 0)
		if len(currentParts) > i {
			if n, err := parseVersionNumber(currentParts[i]); err == nil {
				currentNum = n
			}
		}
		if len(latestParts) > i {
			if n, err := parseVersionNumber(latestParts[i]); err == nil {
				latestNum = n
			}
		}

		if latestNum > currentNum {
			return true
		} else if latestNum < currentNum {
			return false
		}
	}

	return false // Versions are equal
}

func parseVersionNumber(s string) (int, error) {
	// Remove any non-numeric characters for simple parsing
	var num int
	for _, r := range s {
		if r >= '0' && r <= '9' {
			num = num*10 + int(r-'0')
		} else {
			break
		}
	}
	return num, nil
}
