## SQL Style Guide

Purpose

- Codify conventions used across migrations and functions to maximize readability, safety, and maintainability.

General

- Use lowercase SQL keywords and snake_case identifiers.
- Schemas are plural nouns (e.g., `queues`, `comms`, `auth`, `accounts`, `internal`, `api`).
- Avoid deletes/updates for business facts. Prefer append-only tables and derive state with queries and uniqueness constraints.
- Use domains for small enumerations; keep names descriptive and consistent.

Formatting

- Prefer multi-line SQL:
  - Put major clauses on separate lines: `select`, `from`, `join`, `where`, `group by`, `having`, `order by`, `limit`, `returning`.
  - Vertically list selected columns/expressions one per line under `select` if more than one.
  - Single-item lists may remain inline: `select expr`, `order by expr`, `returning expr`.
  - In plpgsql, place `into` on its own line immediately after the `select` list.
  - For `insert`, place the column list on one line (or wrapped), `values` on a new line, and `returning` on a new line; put `into` on its own line when capturing.
  - Wrap subqueries and `exists (...)` predicates; apply the same multi-line rules inside.

Aliases

- Avoid unnecessary table aliases; do not alias single-table queries.
- Use aliases only when required (self-joins, multi-reference joins, or disambiguation).
- Prefer unqualified column names when selecting from a single table.

Function design

- Prefer returning scalars or multiple OUT parameters (avoid named composite types) so callers can assign directly without `select`.
- Prefer direct assignment for single-value or OUT-returning functions: `_var := schema.function(args);` and `return schema.function(args);`.
- Reserve `select ... into` for table/view queries or set-returning functions; avoid it for pure function calls.
- For simple getters, prefer `language sql` functions that directly select needed columns and return them as OUT parameters or a single scalar.
- When a function returns multiple OUT fields, prefer a single `record` variable: `_r record := schema.function(args);` and access via dot notation.
- Prefer using `_r.field` directly instead of copying into separate variables unless transformations warrant it.
- Avoid calling functions with side effects in `declare`; perform side effects in the `begin...end` block. Pure getters may be called in `declare`.
- Rely on getters to normalize inputs; avoid pre-normalizing in callers when getters already handle it.

Further reading

- For architecture, worker contracts, and payload conventions see `docs/postgres/queues-and-worker.md`.

## Navigate

- Back to Postgres: [Postgres Index](README.md)
