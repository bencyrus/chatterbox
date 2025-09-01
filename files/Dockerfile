FROM golang:1.22-alpine
WORKDIR /app
ENV CGO_ENABLED=0
COPY . .
RUN go build -o files ./cmd/files
EXPOSE 8081
CMD ["./files"]
