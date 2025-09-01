Chatterbox

Services

- postgrest: Exposes the API (data access layer over PostgreSQL)
- gateway: Fronts PostgREST; handles token refresh and file URL injection transparently
- caddy: Public reverse proxy/SSL termination (routes external traffic to gateway)

Gateway overview

See gateway/README.md for details on:

- How the gateway refreshes tokens without blocking requests
- How it processes JSON responses to inject signed file URLs
- Environment variables and integration with docker-compose

Local development

- Copy your environment to secrets/.env.gateway (see gateway/README.md for an example)
- Run docker-compose up --build
