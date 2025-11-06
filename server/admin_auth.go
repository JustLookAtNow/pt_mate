package main

import (
    "net/http"
    "os"
    "strconv"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    jwt "github.com/golang-jwt/jwt/v5"
)

type AdminClaims struct {
    Username string `json:"username"`
    jwt.RegisteredClaims
}

func adminCredentials() (string, string) {
    user := os.Getenv("ADMIN_USERNAME")
    pass := os.Getenv("ADMIN_PASSWORD")
    if user == "" { user = "admin" }
    if pass == "" { pass = "change_me" }
    return user, pass
}

func adminSecret() string {
    s := os.Getenv("ADMIN_JWT_SECRET")
    if s == "" { s = "super_secret_key" }
    return s
}

func adminTokenTTL() time.Duration {
    ttlStr := os.Getenv("ADMIN_TOKEN_TTL_HOURS")
    if ttlStr == "" { ttlStr = "168" } // 7 days
    hrs, err := strconv.Atoi(ttlStr)
    if err != nil || hrs <= 0 { hrs = 168 }
    return time.Duration(hrs) * time.Hour
}

// AdminLoginHandler issues a JWT token on successful credential check.
func AdminLoginHandler(c *gin.Context) {
    var req struct{ Username string `json:"username"`; Password string `json:"password"` }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    u, p := adminCredentials()
    if req.Username != u || req.Password != p {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
        return
    }

    ttl := adminTokenTTL()
    now := nowUTC()
    claims := AdminClaims{
        Username: u,
        RegisteredClaims: jwt.RegisteredClaims{
            Subject:   "admin",
            IssuedAt:  jwt.NewNumericDate(now),
            ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
        },
    }

    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    signed, err := token.SignedString([]byte(adminSecret()))
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "生成令牌失败"})
        return
    }
    c.JSON(http.StatusOK, gin.H{"token": signed, "expires_at": claims.ExpiresAt.Time})
}

// AdminAuthMiddleware validates JWT in Authorization: Bearer <token>
func AdminAuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        auth := c.GetHeader("Authorization")
        if !strings.HasPrefix(auth, "Bearer ") {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "未授权"})
            return
        }
        tokenStr := strings.TrimPrefix(auth, "Bearer ")

        token, err := jwt.ParseWithClaims(tokenStr, &AdminClaims{}, func(token *jwt.Token) (interface{}, error) {
            return []byte(adminSecret()), nil
        })
        if err != nil || !token.Valid {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "令牌无效"})
            return
        }
        claims, ok := token.Claims.(*AdminClaims)
        if !ok || claims.Subject != "admin" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "令牌无效"})
            return
        }
        // Attach username for downstream usage
        c.Set("admin_username", claims.Username)
        c.Next()
    }
}