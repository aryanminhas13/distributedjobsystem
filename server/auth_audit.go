package main

import (
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

var roleRank = map[string]int{"viewer": 1, "operator": 2, "admin": 3}

func secureEqual(a, b string) bool {
	return len(a) == len(b) && subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
func requestRole(r *http.Request) string {
	admin, operator, viewer := os.Getenv("ADMIN_TOKEN"), os.Getenv("OPERATOR_TOKEN"), os.Getenv("VIEWER_TOKEN")
	if admin == "" && operator == "" && viewer == "" {
		return "admin"
	}
	token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if token == "" {
		for _, protocol := range strings.Split(r.Header.Get("Sec-WebSocket-Protocol"), ",") {
			protocol = strings.TrimSpace(protocol)
			if strings.HasPrefix(protocol, "bearer.") {
				token = strings.TrimPrefix(protocol, "bearer.")
				break
			}
		}
	}
	if secureEqual(token, admin) && admin != "" {
		return "admin"
	}
	if secureEqual(token, operator) && operator != "" {
		return "operator"
	}
	if secureEqual(token, viewer) && viewer != "" {
		return "viewer"
	}
	return ""
}
func (a *App) authorize(required string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		role := requestRole(r)
		if roleRank[role] < roleRank[required] {
			if role == "" {
				w.Header().Set("WWW-Authenticate", "Bearer")
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next(w, r)
	}
}
func (a *App) audit(r *http.Request, action, target string, metadata any) {
	role := requestRole(r)
	actor := strings.TrimSpace(r.Header.Get("X-Actor-ID"))
	if actor == "" {
		actor = role
	}
	if metadata == nil {
		metadata = map[string]any{}
	}
	a.db.Exec(r.Context(), `INSERT INTO audit_logs(actor,role,action,target,metadata) VALUES($1,$2,$3,$4,$5)`, actor, role, action, target, metadata)
}

func (a *App) listDLQ(w http.ResponseWriter, r *http.Request) {
	rows, e := a.db.Query(r.Context(), selectJob+` WHERE status='failed' ORDER BY dead_lettered_at DESC NULLS LAST LIMIT 100`)
	if e != nil {
		http.Error(w, "could not list dead letters", 500)
		return
	}
	defer rows.Close()
	jobs := []Job{}
	for rows.Next() {
		j, e := scan(rows)
		if e == nil {
			jobs = append(jobs, j)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(jobs)
}
func (a *App) replayDLQ(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	j, e := scan(a.db.QueryRow(r.Context(), `UPDATE jobs SET status='queued',attempts=0,error=NULL,started_at=NULL,finished_at=NULL,dead_lettered_at=NULL,run_at=now() WHERE id=$1 AND status='failed' RETURNING `+jobColumns, id))
	if e != nil {
		http.Error(w, "dead letter not found", 404)
		return
	}
	if e = a.enqueue(r.Context(), id); e != nil {
		a.db.Exec(r.Context(), `UPDATE jobs SET status='failed',error='replay enqueue failed',dead_lettered_at=now() WHERE id=$1`, id)
		http.Error(w, "queue unavailable", 503)
		return
	}
	a.audit(r, "dlq.replay", id, nil)
	a.emit(Event{"job.replayed", j, "Dead-lettered job replayed", j.RunAt})
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(j)
}
func (a *App) listAudit(w http.ResponseWriter, r *http.Request) {
	rows, e := a.db.Query(r.Context(), `SELECT id,actor,role,action,target,metadata,created_at FROM audit_logs ORDER BY created_at DESC LIMIT 200`)
	if e != nil {
		http.Error(w, "could not list audit log", 500)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id int64
		var actor, role, action, target string
		var metadata []byte
		var created time.Time
		if rows.Scan(&id, &actor, &role, &action, &target, &metadata, &created) == nil {
			var m any
			json.Unmarshal(metadata, &m)
			items = append(items, map[string]any{"id": id, "actor": actor, "role": role, "action": action, "target": target, "metadata": m, "createdAt": created})
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}
