package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func TestCompareVersions(t *testing.T) {
	service := &AppService{}

	tests := []struct {
		name     string
		current  string
		latest   string
		expected bool
	}{
		{"Newer Major", "1.0.0", "2.0.0", true},
		{"Newer Minor", "1.1.0", "1.2.0", true},
		{"Newer Patch", "1.1.1", "1.1.2", true},
		{"Same Version", "1.0.0", "1.0.0", false},
		{"Older Major", "2.0.0", "1.0.0", false},
		{"Older Minor", "1.2.0", "1.1.0", false},
		{"Older Patch", "1.1.2", "1.1.1", false},
		{"With v Prefix", "v1.0.0", "v1.0.1", true},
		{"Mixed Prefix", "1.0.0", "v1.0.1", true},
		{"Short Version", "1.0", "1.0.1", true},
		{"Long Version", "1.0.0.1", "1.0.0", false}, // 4th part ignored by current implementation
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := service.compareVersions(tt.current, tt.latest)
			if result != tt.expected {
				t.Errorf("compareVersions(%s, %s) = %v; want %v", tt.current, tt.latest, result, tt.expected)
			}
		})
	}
}

func TestCheckUpdate(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// Setup mock DB
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("an error '%s' was not expected when opening a stub database connection", err)
	}
	defer db.Close()
	mock.MatchExpectationsInOrder(false)

	gormDB, err := gorm.Open(postgres.New(postgres.Config{
		Conn: db,
	}), &gorm.Config{})
	if err != nil {
		t.Fatalf("an error '%s' was not expected when initializing gorm", err)
	}

	service := NewAppService(gormDB)

	tests := []struct {
		name           string
		request        CheckUpdateRequest
		setupMock      func(sqlmock.Sqlmock)
		expectedStatus int
		expectedBody   CheckUpdateResponse
	}{
		{
			name: "Update Available",
			request: CheckUpdateRequest{
				DeviceID:   "test-device",
				Platform:   "android",
				AppVersion: "1.0.0",
				IsBeta:     false,
			},
			setupMock: func(mock sqlmock.Sqlmock) {
				// 1. updateStatistics
				// First check if exists
				mock.ExpectQuery(`SELECT \* FROM "app_statistics" WHERE device_id = \$1 ORDER BY "app_statistics"."id" LIMIT \$2`).
					WithArgs("test-device", 1).
					WillReturnRows(sqlmock.NewRows([]string{"id", "total_launches"}).AddRow(1, 10))
				// Update
				mock.ExpectBegin()
				mock.ExpectExec(`UPDATE "app_statistics" SET`).
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectCommit()

				// 2. recordDailyActivity
				mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO app_activity (device_id, platform, app_version, seen_date, seen_at)
            VALUES ($1, $2, $3, ($4::date), $5)
            ON CONFLICT (device_id, seen_date) DO NOTHING`)).
					WillReturnResult(sqlmock.NewResult(1, 1))

				// 3. getLatestVersion
				mock.ExpectQuery(`SELECT \* FROM "app_versions" WHERE .*is_latest = \$1 AND is_published = \$2.*is_beta = \$3.* LIMIT \$4`).
					WithArgs(true, true, false, 1).
					WillReturnRows(sqlmock.NewRows([]string{"version", "release_notes", "download_url", "android_download_url", "is_latest", "is_beta", "is_published", "created_at"}).
						AddRow("1.1.0", "New features", "https://example.com/release", "http://example.com/app.apk", true, false, true, time.Now()))
			},
			expectedStatus: http.StatusOK,
			expectedBody: CheckUpdateResponse{
				HasUpdate:          true,
				LatestVersion:      "1.1.0",
				ReleaseNotes:       "New features",
				DownloadURL:        "http://example.com/app.apk",
				AndroidDownloadURL: "http://example.com/app.apk",
			},
		},
		{
			name: "No Update Available",
			request: CheckUpdateRequest{
				DeviceID:   "test-device",
				Platform:   "android",
				AppVersion: "2.0.0",
				IsBeta:     false,
			},
			setupMock: func(mock sqlmock.Sqlmock) {
				// 1. updateStatistics
				mock.ExpectQuery(`SELECT \* FROM "app_statistics" WHERE device_id = \$1 ORDER BY "app_statistics"."id" LIMIT \$2`).
					WithArgs("test-device", 1).
					WillReturnRows(sqlmock.NewRows([]string{"id", "total_launches"}).AddRow(1, 10))
				mock.ExpectBegin()
				mock.ExpectExec(`UPDATE "app_statistics" SET`).
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectCommit()

				// 2. recordDailyActivity
				mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO app_activity (device_id, platform, app_version, seen_date, seen_at)
            VALUES ($1, $2, $3, ($4::date), $5)
            ON CONFLICT (device_id, seen_date) DO NOTHING`)).
					WillReturnResult(sqlmock.NewResult(1, 1))

				// 3. getLatestVersion
				mock.ExpectQuery(`SELECT \* FROM "app_versions" WHERE .*is_latest = \$1 AND is_published = \$2.*is_beta = \$3.* LIMIT \$4`).
					WithArgs(true, true, false, 1).
					WillReturnRows(sqlmock.NewRows([]string{"version", "release_notes", "download_url", "android_download_url", "is_latest", "is_beta", "is_published", "created_at"}).
						AddRow("1.1.0", "New features", "https://example.com/release", "http://example.com/app.apk", true, false, true, time.Now()))
			},
			expectedStatus: http.StatusOK,
			expectedBody: CheckUpdateResponse{
				HasUpdate: false,
			},
		},
		{
			name: "Update Available For Non-Android Keeps Generic URL",
			request: CheckUpdateRequest{
				DeviceID:   "test-device",
				Platform:   "ios",
				AppVersion: "1.0.0",
				IsBeta:     false,
			},
			setupMock: func(mock sqlmock.Sqlmock) {
				mock.ExpectQuery(`SELECT \* FROM "app_statistics" WHERE device_id = \$1 ORDER BY "app_statistics"."id" LIMIT \$2`).
					WithArgs("test-device", 1).
					WillReturnRows(sqlmock.NewRows([]string{"id", "total_launches"}).AddRow(1, 10))
				mock.ExpectBegin()
				mock.ExpectExec(`UPDATE "app_statistics" SET`).
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectCommit()

				mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO app_activity (device_id, platform, app_version, seen_date, seen_at)
            VALUES ($1, $2, $3, ($4::date), $5)
            ON CONFLICT (device_id, seen_date) DO NOTHING`)).
					WillReturnResult(sqlmock.NewResult(1, 1))

				mock.ExpectQuery(`SELECT \* FROM "app_versions" WHERE .*is_latest = \$1 AND is_published = \$2.*is_beta = \$3.* LIMIT \$4`).
					WithArgs(true, true, false, 1).
					WillReturnRows(sqlmock.NewRows([]string{"version", "release_notes", "download_url", "android_download_url", "is_latest", "is_beta", "is_published", "created_at"}).
						AddRow("1.1.0", "New features", "https://example.com/release", "http://example.com/app.apk", true, false, true, time.Now()))
			},
			expectedStatus: http.StatusOK,
			expectedBody: CheckUpdateResponse{
				HasUpdate:          true,
				LatestVersion:      "1.1.0",
				ReleaseNotes:       "New features",
				DownloadURL:        "https://example.com/release",
				AndroidDownloadURL: "http://example.com/app.apk",
			},
		},
		{
			name: "No Versions in DB",
			request: CheckUpdateRequest{
				DeviceID:   "test-device",
				Platform:   "android",
				AppVersion: "1.0.0",
				IsBeta:     false,
			},
			setupMock: func(mock sqlmock.Sqlmock) {
				// 1. updateStatistics
				mock.ExpectQuery(`SELECT \* FROM "app_statistics" WHERE device_id = \$1 ORDER BY "app_statistics"."id" LIMIT \$2`).
					WithArgs("test-device", 1).
					WillReturnRows(sqlmock.NewRows([]string{"id", "total_launches"}).AddRow(1, 10))
				mock.ExpectBegin()
				mock.ExpectExec(`UPDATE "app_statistics" SET`).
					WillReturnResult(sqlmock.NewResult(1, 1))
				mock.ExpectCommit()

				// 2. recordDailyActivity
				mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO app_activity (device_id, platform, app_version, seen_date, seen_at)
            VALUES ($1, $2, $3, ($4::date), $5)
            ON CONFLICT (device_id, seen_date) DO NOTHING`)).
					WillReturnResult(sqlmock.NewResult(1, 1))

				// 3. getLatestVersion - RecordNotFound
				mock.ExpectQuery(`SELECT \* FROM "app_versions" WHERE .*is_latest = \$1 AND is_published = \$2.*is_beta = \$3.* LIMIT \$4`).
					WithArgs(true, true, false, 1).
					WillReturnError(gorm.ErrRecordNotFound)
			},
			expectedStatus: http.StatusOK,
			expectedBody: CheckUpdateResponse{
				HasUpdate: false,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.setupMock(mock)

			// Create request
			body, _ := json.Marshal(tt.request)
			req, _ := http.NewRequest(http.MethodPost, "/api/v1/check-update", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = req

			// Call handler
			service.CheckUpdate(c)
			time.Sleep(20 * time.Millisecond)

			// Assertions
			assert.Equal(t, tt.expectedStatus, w.Code)

			var response CheckUpdateResponse
			err := json.Unmarshal(w.Body.Bytes(), &response)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedBody, response)

			// Ensure all expectations were met
			assert.NoError(t, mock.ExpectationsWereMet())
		})
	}
}
