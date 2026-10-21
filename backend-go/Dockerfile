# Multi-stage Dockerfile for Tashil Data Sharing Cloud Run Service
# Stage 1: Build binary
FROM golang:alpine AS builder

WORKDIR /app

RUN apk add --no-cache git ca-certificates

COPY go.mod go.sum* ./
RUN go mod download || true

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /app/server ./cmd/server/main.go

# Stage 2: Minimal scratch / distroless runtime
FROM alpine:3.19

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/server /usr/local/bin/tashil-server
COPY data /app/data

RUN chmod -R 777 /app/data

ENV PORT=8080
ENV ENVIRONMENT=production
ENV USE_MOCK_SERVICES=false
ENV TASHIL_ARCHIVE_DIR=/app/data/archive

EXPOSE 8080

USER nobody:nobody

ENTRYPOINT ["/usr/local/bin/tashil-server"]
