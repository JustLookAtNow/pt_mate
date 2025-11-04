package main

import (
    "database/sql"
    "net/http"
    "os"
    "strings"

    "github.com/gin-gonic/gin"
)

type VersionService struct {
	db *sql.DB
}

func NewVersionService(db *sql.DB) *VersionService {
	return &VersionService{db: db}
}

func (s *VersionService) UpdateVersion(c *gin.Context) {
    // Verify webhook secret if configured
    secret := os.Getenv("GITHUB_WEBHOOK_SECRET")
    if secret != "" {
        provided := c.GetHeader("X-Webhook-Secret")
        if provided == "" {
            // Also support Authorization: Bearer <token>
            auth := c.GetHeader("Authorization")
            if strings.HasPrefix(auth, "Bearer ") {
                provided = strings.TrimPrefix(auth, "Bearer ")
            } else {
                // Fallback to query param token
                provided = c.Query("token")
            }
        }

        if provided == "" || provided != secret {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized: invalid webhook secret"})
            return
        }
    }

    var req VersionUpdateRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

	// Start transaction
	tx, err := s.db.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to start transaction"})
		return
	}
	defer tx.Rollback()

    // Set all existing versions to not latest
    _, err = tx.Exec("UPDATE app_versions SET is_latest = false")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update existing versions"})
		return
	}

	// Check if version already exists
	var existingID int
	err = tx.QueryRow("SELECT id FROM app_versions WHERE version = $1", req.Version).Scan(&existingID)
	
    if err == sql.ErrNoRows {
        // Insert new version
        // infer beta by version suffix containing '-' or beta/alpha/rc markers
        isBeta := inferBeta(req.Version)
        _, err = tx.Exec(`
            INSERT INTO app_versions (version, release_notes, download_url, is_latest, is_beta, created_at, updated_at)
            VALUES ($1, $2, $3, true, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `, req.Version, req.ReleaseNotes, req.DownloadURL, isBeta)
		
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to insert new version"})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check existing version"})
		return
    } else {
        // Update existing version
        isBeta := inferBeta(req.Version)
        _, err = tx.Exec(`
            UPDATE app_versions 
            SET release_notes = $2, download_url = $3, is_latest = true, is_beta = $4, updated_at = CURRENT_TIMESTAMP
            WHERE id = $1
        `, existingID, req.ReleaseNotes, req.DownloadURL, isBeta)
		
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update existing version"})
			return
		}
	}

	// Commit transaction
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to commit transaction"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Version updated successfully",
		"version": req.Version,
	})
}

func inferBeta(version string) bool {
    v := strings.ToLower(version)
    return strings.Contains(v, "-") || strings.Contains(v, "alpha") || strings.Contains(v, "beta") || strings.Contains(v, "rc") || strings.Contains(v, "preview") || strings.Contains(v, "pre")
}