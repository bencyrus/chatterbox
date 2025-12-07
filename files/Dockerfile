FROM golang:1.24-alpine
WORKDIR /app
ENV CGO_ENABLED=0
COPY . .
WORKDIR /app/files
RUN go build -o files ./cmd/files
EXPOSE 8081
CMD ["./files"]
