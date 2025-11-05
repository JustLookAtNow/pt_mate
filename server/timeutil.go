package main

import "time"

// nowUTC returns current time in UTC. Used to ensure
// consistent timestamp storage with TIMESTAMPTZ columns.
func nowUTC() time.Time {
    return time.Now().UTC()
}