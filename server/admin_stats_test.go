package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func newMockGormDB(t *testing.T) (*gorm.DB, sqlmock.Sqlmock, func()) {
	t.Helper()

	db, mock, err := sqlmock.New()
	require.NoError(t, err)

	gormDB, err := gorm.Open(postgres.New(postgres.Config{
		Conn: db,
	}), &gorm.Config{})
	require.NoError(t, err)

	return gormDB, mock, func() {
		mock.ExpectClose()
		assert.NoError(t, db.Close())
		assert.NoError(t, mock.ExpectationsWereMet())
	}
}

func TestBucketVersionStatsRowsTopNWithOther(t *testing.T) {
	rows := []versionStatsRow{
		{Version: "2.25.2", Count: 9},
		{Version: "2.25.1", Count: 8},
		{Version: "2.24.0", Count: 7},
		{Version: "2.23.0", Count: 6},
	}

	got := bucketVersionStatsRows(rows, 2)

	require.Len(t, got, 3)
	assert.Equal(t, versionStatsRow{Version: "2.25.2", Count: 9}, got[0])
	assert.Equal(t, versionStatsRow{Version: "2.25.1", Count: 8}, got[1])
	assert.Equal(t, versionStatsRow{Version: otherVersionLabel, Count: 13, IsOther: true}, got[2])
}

func TestBucketVersionStatsRowsNoOtherWithinLimit(t *testing.T) {
	rows := []versionStatsRow{
		{Version: "2.25.2", Count: 9},
		{Version: "2.25.1", Count: 8},
	}

	got := bucketVersionStatsRows(rows, 8)

	require.Len(t, got, 2)
	assert.False(t, got[0].IsOther)
	assert.False(t, got[1].IsOther)
}

func TestAdminStatsVersionsReturnsTopNAndOther(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, mock, cleanup := newMockGormDB(t)
	defer cleanup()

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT s.app_version AS version, COUNT(*) AS count
FROM app_statistics s
GROUP BY s.app_version
ORDER BY COUNT(*) DESC, s.app_version ASC`)).
		WillReturnRows(sqlmock.NewRows([]string{"version", "count"}).
			AddRow("2.25.0", 5).
			AddRow("2.24.0", 4).
			AddRow("2.23.0", 3).
			AddRow("2.22.0", 2))

	req, _ := http.NewRequest(http.MethodGet, "/api/v1/admin/stats/versions?limit=2", nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = req

	AdminStatsVersions(db)(c)

	require.Equal(t, http.StatusOK, w.Code)

	var body struct {
		Items []versionStatsRow `json:"items"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	require.Len(t, body.Items, 3)
	assert.Equal(t, versionStatsRow{Version: "2.25.0", Count: 5}, body.Items[0])
	assert.Equal(t, versionStatsRow{Version: "2.24.0", Count: 4}, body.Items[1])
	assert.Equal(t, versionStatsRow{Version: otherVersionLabel, Count: 5, IsOther: true}, body.Items[2])
}

func TestAdminStatsDevicesOtherBucketFiltersOutTopVersions(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, mock, cleanup := newMockGormDB(t)
	defer cleanup()

	mock.MatchExpectationsInOrder(true)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT s.app_version AS version, COUNT(*) AS count
FROM app_statistics s
GROUP BY s.app_version
ORDER BY COUNT(*) DESC, s.app_version ASC`)).
		WillReturnRows(sqlmock.NewRows([]string{"version", "count"}).
			AddRow("2.25.0", 10).
			AddRow("2.24.0", 9).
			AddRow("2.23.0", 1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT count(*) FROM "app_statistics" WHERE app_version NOT IN ($1,$2)`)).
		WithArgs("2.25.0", "2.24.0").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(1))
	mock.ExpectQuery(`SELECT .* FROM "app_statistics" WHERE app_version NOT IN \(\$1,\$2\) ORDER BY last_seen DESC LIMIT \$3`).
		WithArgs("2.25.0", "2.24.0", 20).
		WillReturnRows(sqlmock.NewRows([]string{
			"device_id", "platform", "app_version", "first_seen", "last_seen", "total_launches", "ip",
		}).AddRow("device-1", "android", "2.23.0", time.Now(), time.Now(), 3, "127.0.0.1"))

	req, _ := http.NewRequest(http.MethodGet, "/api/v1/admin/stats/devices?version_bucket=other&version_limit=2", nil)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = req

	AdminStatsDevices(db)(c)

	require.Equal(t, http.StatusOK, w.Code)

	var body struct {
		Total int64 `json:"total"`
		Items []struct {
			DeviceID   string `json:"device_id"`
			AppVersion string `json:"app_version"`
		} `json:"items"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
	assert.Equal(t, int64(1), body.Total)
	require.Len(t, body.Items, 1)
	assert.Equal(t, "device-1", body.Items[0].DeviceID)
	assert.Equal(t, "2.23.0", body.Items[0].AppVersion)
}
