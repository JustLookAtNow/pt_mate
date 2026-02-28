package main

import (
	"net/http"
	"os"
	"strconv"
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

func (s *VersionService) AdminListVersions(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "30"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 30
	}

	var total int64
	s.db.Model(&AppVersion{}).Count(&total)

	var versions []AppVersion
	offset := (page - 1) * pageSize
	if err := s.db.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&versions).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch versions"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"items": versions,
		"total": total,
	})
}

func (s *VersionService) AdminUpdateVersion(c *gin.Context) {
    id := c.Param("id")
    var req AdminUpdateVersionRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    if err := s.db.Transaction(func(tx *gorm.DB) error {
        var v AppVersion
        if err := tx.First(&v, id).Error; err != nil {
            return err
        }

        if req.ReleaseNotes != nil {
            v.ReleaseNotes = *req.ReleaseNotes
        }
        if req.DownloadURL != nil {
            v.DownloadURL = *req.DownloadURL
        }
        if req.IsBeta != nil {
            v.IsBeta = *req.IsBeta
        }
        if req.IsPublished != nil {
            v.IsPublished = *req.IsPublished
        }

        if req.IsLatest != nil && *req.IsLatest {
            // Unset other latest
            if err := tx.Model(&AppVersion{}).Where("is_latest = ?", true).Update("is_latest", false).Error; err != nil {
                return err
            }
            v.IsLatest = true
        } else if req.IsLatest != nil && !*req.IsLatest {
            v.IsLatest = false
        }

        v.UpdatedAt = nowUTC()
        return tx.Save(&v).Error
    }); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update version: " + err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{"message": "Version updated successfully"})
}

func (s *VersionService) AdminDeleteVersion(c *gin.Context) {
    id := c.Param("id")
    if err := s.db.Delete(&AppVersion{}, id).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete version"})
        return
    }
    c.JSON(http.StatusOK, gin.H{"message": "Version deleted successfully"})
}