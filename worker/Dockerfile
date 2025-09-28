FROM golang:1.22-alpine
WORKDIR /app
ENV CGO_ENABLED=0
COPY . .
WORKDIR /app/worker
RUN go build -o worker ./cmd/worker
CMD ["./worker"]
