FROM golang:1.24-alpine AS builder

WORKDIR /app

COPY . .

RUN go build -o like_service ./cmd/like_service/main.go

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/like_service .
COPY --from=builder /app/config.yaml .
COPY --from=builder /app/migrations ./migrations

EXPOSE 8086

CMD ./like_service config.yaml
