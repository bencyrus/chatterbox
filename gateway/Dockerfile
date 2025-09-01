FROM golang:1.22-alpine
WORKDIR /app
ENV CGO_ENABLED=0
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o gateway ./cmd/gateway
EXPOSE 8080
CMD ["./gateway"]
