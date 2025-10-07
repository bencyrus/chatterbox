## Why the Supervisor Pattern

We use supervisors because real systems spend most of their time waiting: on networks, providers, users, or other events. The question is not whether we wait, but where we absorb that waiting and how we keep the system understandable while we do.

### The real trade‑off: where to put variability

Long, synchronous requests push all variability to the edge. That looks simple until load rises: threads block, connections pile up, and a single slow dependency ripples through the system. Supervisors move the variability inside the system as short, independent steps. Each step does a small read‑think‑write and then gets out of the way. The total work is the same at low volume, but under load the behavior is radically different: small steps queue and drain predictably instead of amplifying contention.

### Why small steps feel safer

Small steps are easy to reason about: they fetch current facts, make one decision, append one fact, and stop. When something fails, we haven’t tangled side effects inside a long transaction—we have a clear record of what happened up to that point. We can re‑run a step because the next decision is derived from the facts we’ve already recorded. That makes timing issues, out‑of‑order arrivals, and retries tolerable rather than frightening.

### Why put the brain in the database

Business state lives in the database. Keeping supervision logic next to that state means decisions are made with the freshest facts and the fewest moving parts. We don’t need to pass around snapshots or keep long‑lived in‑memory flows. The database becomes both the source of truth and the logbook of how we got there.

### The thing we’re avoiding: big unsupervised work

Big queries and unsupervised batch jobs can be fine, until they aren’t. Data grows, inputs shift, and a once‑innocent job suddenly locks a table or blows through memory. Breaking work into supervised steps keeps the same intent but removes the blast radius. Each step is bounded in scope and time; if one spikes, it spikes alone.

### Running while we sleep

There’s a difference between pushing a button while watching graphs and setting something loose at 2 a.m. Supervisors give unattended work a steady hand: a place to decide what’s next, when to try again, and when to stop. The history is in the facts; the operating room is calm even if the world outside is messy.

### Two stories

1. Out‑of‑order events

Two webhooks arrive in any order; say, checkout completion and subscription creation. Each arrival writes its fact, then calls the supervisor. The supervisor checks what exists now: if both are present and one implies failure, it takes the failure path; if both are present and healthy, it records success; if one is still missing, it does nothing yet. No timers are held open, and no guesswork is required; the next fact will bring the supervisor back.

2. Sending an email

We create a “send email” task and ask the supervisor to shepherd it. The first run sees no success, records one “scheduled” attempt, and enqueues the email. If the provider fails, the failure fact is written. The next run notices one failure and, if within limits, schedules exactly one more attempt. When success arrives, the supervisor sees the terminal fact and stops. The process is visible at every step and cannot double‑schedule by accident because each decision is grounded in counts of facts.

### What we gain

Under load, small supervised steps degrade gracefully. Because state is derived from facts instead of in‑place mutation, decisions are deterministic and safe to retry. And because every step leaves a breadcrumb, we get an honest audit trail for both business outcomes and operational errors.

This is why we use supervisors: to keep waiting out of request threads, keep decisions close to the truth, and move forward one safe step at a time.

Navigate

- Back to docs: [Docs Index](README.md)
- Concepts: [Concepts](concepts/README.md)
