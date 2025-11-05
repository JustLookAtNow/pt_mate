# Database Migrations

This directory contains schema migrations managed by Goose.

## Usage

Initialize the database and apply migrations:

```
go run ./server/cmd/migrate up
```

Rollback last migration:

```
go run ./server/cmd/migrate down
```

Status:

```
go run ./server/cmd/migrate status
```

## Notes

- All timestamps are stored as `TIMESTAMPTZ` in UTC.
- Existing `TIMESTAMP` columns are converted using `AT TIME ZONE` and then altered to `TIMESTAMPTZ`.