package main

import (
    "net/http"
    "os"
    "strings"

    "github.com/gin-gonic/gin"
    "gorm.io/gorm"
)

type VersionService struct {
    db *gorm.DB
}

func NewVersionService(db *gorm.DB) *VersionService {
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
    // Start transaction (GORM)
    if err := s.db.Transaction(func(tx *gorm.DB) error {
        // Set all existing versions to not latest
        if err := tx.Model(&AppVersion{}).Where("is_latest = ?", true).Update("is_latest", false).Error; err != nil {
            return err
        }

        var existing AppVersion
        err := tx.Where("version = ?", req.Version).First(&existing).Error
        isBeta := inferBeta(req.Version)

        if err == gorm.ErrRecordNotFound {
            // Insert new version
            v := AppVersion{
                Version:      req.Version,
                ReleaseNotes: req.ReleaseNotes,
                DownloadURL:  req.DownloadURL,
                IsLatest:     true,
                IsBeta:       isBeta,
                CreatedAt:    nowUTC(),
                UpdatedAt:    nowUTC(),
            }
            return tx.Create(&v).Error
        } else if err != nil {
            return err
        } else {
            // Update existing version
            existing.ReleaseNotes = req.ReleaseNotes
            existing.DownloadURL = req.DownloadURL
            existing.IsLatest = true
            existing.IsBeta = isBeta
            existing.UpdatedAt = nowUTC()
            return tx.Save(&existing).Error
        }
    }); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update version"})
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