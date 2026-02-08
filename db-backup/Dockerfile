FROM golang:1.24-alpine AS build
WORKDIR /app
ENV CGO_ENABLED=0
COPY . .
WORKDIR /app/db-backup
RUN go build -o db-backup ./cmd/db-backup

FROM alpine:3.21
RUN apk add --no-cache postgresql16-client gzip
COPY --from=build /app/db-backup/db-backup /usr/local/bin/db-backup
CMD ["db-backup"]
