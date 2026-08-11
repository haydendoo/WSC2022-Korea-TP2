# Practice-compatible "root" service image.
# Multi-stage build: compile a linux/amd64 binary, then ship it in a
# minimal base image. No config is baked in - configuration is fetched
# from AWS AppConfig at runtime (APPCONFIG_APPLICATION/APPCONFIG_ENVIRONMENT
# /APPCONFIG_PROFILE), or, for local testing without AWS, from a JSON file
# mounted at /app/config.json (see config/root.example.json and
# docker/docker-compose.yaml).

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/root .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/root ./root

EXPOSE 80
ENTRYPOINT ["./root"]
CMD ["--config", "/app/config.json"]
