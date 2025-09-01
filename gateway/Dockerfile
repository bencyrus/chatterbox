FROM golang:1.22-alpine
WORKDIR /app
ENV CGO_ENABLED=0
COPY . .
WORKDIR /app/gateway
RUN go build -o gateway ./cmd/gateway
EXPOSE 8080
CMD ["./gateway"]
