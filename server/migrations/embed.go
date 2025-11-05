package migrations

import "embed"

// FS embeds all SQL migration files for packaging into binaries.
//go:embed *.sql
var FS embed.FS