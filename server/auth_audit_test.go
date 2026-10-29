package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequestRoleLocalMode(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "")
	t.Setenv("OPERATOR_TOKEN", "")
	t.Setenv("VIEWER_TOKEN", "")

	if got := requestRole(httptest.NewRequest(http.MethodGet, "/api/jobs", nil)); got != "admin" {
		t.Fatalf("requestRole() = %q, want admin", got)
	}
}

func TestRequestRoleBearerAndWebSocket(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "admin-secret")
	t.Setenv("OPERATOR_TOKEN", "operator-secret")
	t.Setenv("VIEWER_TOKEN", "viewer-secret")

	trequest := httptest.NewRequest(http.MethodGet, "/api/jobs", nil)
	trequest.Header.Set("Authorization", "Bearer operator-secret")
	if got := requestRole(trequest); got != "operator" {
		t.Fatalf("Bearer request role = %q, want operator", got)
	}

	wsRequest := httptest.NewRequest(http.MethodGet, "/ws", nil)
	wsRequest.Header.Set("Sec-WebSocket-Protocol", "other, bearer.viewer-secret")
	if got := requestRole(wsRequest); got != "viewer" {
		t.Fatalf("WebSocket request role = %q, want viewer", got)
	}
}

func TestAuthorizeEnforcesRoleRank(t *testing.T) {
	t.Setenv("ADMIN_TOKEN", "admin-secret")
	t.Setenv("OPERATOR_TOKEN", "operator-secret")
	t.Setenv("VIEWER_TOKEN", "viewer-secret")

	app := &App{}
	called := false
	handler := app.authorize("operator", func(w http.ResponseWriter, _ *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	viewerRequest := httptest.NewRequest(http.MethodPost, "/api/jobs", nil)
	viewerRequest.Header.Set("Authorization", "Bearer viewer-secret")
	viewerResponse := httptest.NewRecorder()
	handler(viewerResponse, viewerRequest)
	if viewerResponse.Code != http.StatusForbidden || called {
		t.Fatalf("viewer response = %d, called = %v", viewerResponse.Code, called)
	}

	operatorRequest := httptest.NewRequest(http.MethodPost, "/api/jobs", nil)
	operatorRequest.Header.Set("Authorization", "Bearer operator-secret")
	operatorResponse := httptest.NewRecorder()
	handler(operatorResponse, operatorRequest)
	if operatorResponse.Code != http.StatusNoContent || !called {
		t.Fatalf("operator response = %d, called = %v", operatorResponse.Code, called)
	}
}
