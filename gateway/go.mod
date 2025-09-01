module github.com/bencyrus/chatterbox/gateway

go 1.22

require (
	github.com/bencyrus/chatterbox/shared v0.0.0
	github.com/golang-jwt/jwt/v5 v5.2.1
)

replace github.com/bencyrus/chatterbox/shared => ../shared
