package main

import (
	"database/sql"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type AppService struct {
	db *sql.DB
}

func NewAppService(db *sql.DB) *AppService {
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

    // Update or insert statistics
    if err := s.updateStatistics(req.DeviceID, req.Platform, req.AppVersion, clientIP); err != nil {
        log.Printf("Failed to update statistics: %v", err)
        // Don't fail the request if statistics update fails
    }

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
    // Check if device exists
    var exists bool
    err := s.db.QueryRow(`
        SELECT EXISTS(SELECT 1 FROM app_statistics WHERE device_id = $1)
    `, deviceID).Scan(&exists)

	if err != nil {
		return err
	}

    if exists {
        // Update existing record
        _, err = s.db.Exec(`
            UPDATE app_statistics 
            SET platform = $2, app_version = $3, ip = $4, last_seen = CURRENT_TIMESTAMP, total_launches = total_launches + 1
            WHERE device_id = $1
        `, deviceID, platform, appVersion, ip)
    } else {
        // Insert new record
        _, err = s.db.Exec(`
            INSERT INTO app_statistics (device_id, platform, app_version, ip, first_seen, last_seen, total_launches)
            VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
        `, deviceID, platform, appVersion, ip)
    }

    return err
}

func (s *AppService) getLatestVersion(includeBeta bool) (*AppVersion, error) {
    var version AppVersion
    query := `SELECT id, version, release_notes, download_url, is_latest, is_beta, created_at, updated_at
              FROM app_versions 
              WHERE is_latest = true `
    if !includeBeta {
        query += `AND (is_beta = false OR is_beta IS NULL) `
    }
    query += `ORDER BY created_at DESC LIMIT 1`
    err := s.db.QueryRow(query).Scan(
        &version.ID,
        &version.Version,
        &version.ReleaseNotes,
        &version.DownloadURL,
        &version.IsLatest,
        &version.IsBeta,
        &version.CreatedAt,
        &version.UpdatedAt,
    )

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
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
