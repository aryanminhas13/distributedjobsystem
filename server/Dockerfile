FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/orchestrator .
FROM alpine:3.20
COPY --from=build /out/orchestrator /app/orchestrator
ENTRYPOINT ["/app/orchestrator"]
