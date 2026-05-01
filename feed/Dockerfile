FROM golang:1.24-alpine AS builder

WORKDIR /app

COPY . .

RUN go build -o feed_service ./cmd/feed_service/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/feed_service .
COPY --from=builder /app/migrations ./migrations

EXPOSE 8080

CMD ["./feed_service", "config.yaml"]
