module github.com/bencyrus/chatterbox/worker

go 1.22

require (
	github.com/bencyrus/chatterbox/shared v0.0.0
	github.com/lib/pq v1.10.9
)

replace github.com/bencyrus/chatterbox/shared => ../shared
