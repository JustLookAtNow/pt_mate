package main

import "time"

// CheckUpdateRequest represents the request payload for update checking
type CheckUpdateRequest struct {
    DeviceID    string `json:"device_id" binding:"required"`
    Platform    string `json:"platform" binding:"required"`
    AppVersion  string `json:"app_version" binding:"required"`
    IsBeta      bool   `json:"is_beta"`
}

// CheckUpdateResponse represents the response for update checking
type CheckUpdateResponse struct {
	HasUpdate    bool   `json:"has_update"`
	LatestVersion string `json:"latest_version,omitempty"`
	ReleaseNotes  string `json:"release_notes,omitempty"`
	DownloadURL   string `json:"download_url,omitempty"`
}

// VersionUpdateRequest represents the request from GitHub Actions
type VersionUpdateRequest struct {
	Version      string `json:"version" binding:"required"`
	ReleaseNotes string `json:"release_notes"`
	DownloadURL  string `json:"download_url"`
}

// AppVersion represents a version record in database
type AppVersion struct {
    ID           int       `json:"id" gorm:"primaryKey"`
    Version      string    `json:"version" gorm:"uniqueIndex;size:50;not null"`
    ReleaseNotes string    `json:"release_notes"`
    DownloadURL  string    `json:"download_url" gorm:"size:500"`
    IsLatest     bool      `json:"is_latest" gorm:"index"`
    IsBeta       bool      `json:"is_beta" gorm:"index"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

// AppStatistic represents usage statistics in database
type AppStatistic struct {
    ID            int       `json:"id" gorm:"primaryKey"`
    DeviceID      string    `json:"device_id" gorm:"uniqueIndex;size:100;not null"`
    Platform      string    `json:"platform" gorm:"index;size:50;not null"`
    AppVersion    string    `json:"app_version" gorm:"size:50;not null"`
    IP            string    `json:"ip" gorm:"size:64"`
    FirstSeen     time.Time `json:"first_seen"`
    LastSeen      time.Time `json:"last_seen" gorm:"index"`
    TotalLaunches int       `json:"total_launches"`
}