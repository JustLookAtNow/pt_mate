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
    ID           int       `json:"id"`
    Version      string    `json:"version"`
    ReleaseNotes string    `json:"release_notes"`
    DownloadURL  string    `json:"download_url"`
    IsLatest     bool      `json:"is_latest"`
    IsBeta       bool      `json:"is_beta"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

// AppStatistic represents usage statistics in database
type AppStatistic struct {
    ID            int       `json:"id"`
    DeviceID      string    `json:"device_id"`
    Platform      string    `json:"platform"`
    AppVersion    string    `json:"app_version"`
    IP            string    `json:"ip"`
    FirstSeen     time.Time `json:"first_seen"`
    LastSeen      time.Time `json:"last_seen"`
    TotalLaunches int       `json:"total_launches"`
}