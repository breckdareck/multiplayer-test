# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies.
Assumes the vocabulary in [LANGUAGE.md](LANGUAGE.md) — **module**,
**interface**, **seam**, **adapter**.

## Dependency categories

When assessing a candidate for deepening, classify its dependencies. The
category determines how the deepened module is tested across its seam.

### 1. In-process

Pure computation, in-memory state, no I/O. Always deepenable — merge the
modules and test through the new interface directly. No adapter needed.

In this codebase: stat formulas, hit-chance math, damage rolls, level curves,
buff resolution, ability scaling. The `balance_simulator` addon already tests
some of these through their formula interface — that's the shape to aim for.

### 2. Local-substitutable

Dependencies that have local test stand-ins (PGLite for Postgres, in-memory
filesystem). Deepenable if the stand-in exists. The deepened module is
tested with the stand-in running in the test suite. The seam is internal; no
port at the module's external interface.

In this codebase: anything backed by `user://` paths, or by the SaveManager's
on-disk JSON. A test-only in-memory FS adapter is the substitutable.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (microservices, internal APIs).
Define a **port** (interface) at the seam. The deep module owns the logic;
the transport is injected as an **adapter**. Tests use an in-memory adapter.
Production uses an HTTP/gRPC/queue adapter.

In this codebase: the Flask backend (`NetworkManager` → `backend/`). The deep
module is the player/character-record logic; the HTTP transport is one
adapter, an in-memory adapter is the test stand-in. The ENet server/client
seam (`ServerManager` / `ClientManager`) is also this category — RPCs are
the wire, the gameplay module owns the logic.

Recommendation shape: *"Define a port at the seam, implement an HTTP adapter
for production and an in-memory adapter for testing, so the logic sits in
one deep module even though it's deployed across a network."*

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. The deepened
module takes the external dependency as an injected port; tests provide a
mock adapter.

In this codebase: none today. If voice chat, payments, or analytics get added,
they land here.

## Seam discipline

- **One adapter means a hypothetical seam. Two adapters means a real one.**
  Don't introduce a port unless at least two adapters are justified
  (typically production + test). A single-adapter seam is just indirection.
- **Internal seams vs external seams.** A deep module can have internal seams
  (private to its implementation, used by its own tests) as well as the
  external seam at its interface. Don't expose internal seams through the
  interface just because tests use them.
- **The server-authority seam is non-negotiable.** Client and server are
  *always* two adapters (or more, once bots are counted). Never propose
  collapsing it.

## Testing strategy: replace, don't layer

- Old unit tests on shallow modules become waste once tests at the deepened
  module's interface exist — delete them.
- Write new tests at the deepened module's interface. The **interface is
  the test surface**.
- Tests assert on observable outcomes through the interface, not internal
  state.
- Tests should survive internal refactors — they describe behaviour, not
  implementation. If a test has to change when the implementation changes,
  it's testing past the interface.

## Godot-specific gotchas

- **Autoloads are singletons with global state.** Deepening across multiple
  autoloads usually means *folding one into another*, not introducing a new
  one. New autoloads are almost never the answer — the root
  [CLAUDE.md](../../../CLAUDE.md) is explicit on this.
- **RPCs are part of the interface.** The signature isn't the whole picture —
  the RPC mode (`authority`/`any_peer`, `call_local`/`call_remote`,
  `reliable`/`unreliable`), the peer-ID expectations, and the group-membership
  contracts are all part of what callers must know.
- **`.tres` data is part of the interface.** A deep module that consumes
  `AbilityData` has the fields of `AbilityData` in its interface — adding a
  field is an interface change, even if no GDScript signature moves.
- **Signals are part of the interface.** When a module fans out via signals,
  every connected listener is a caller. Counting only direct method callers
  underestimates depth.
- **The `networked_entities` group is part of the interface.** Any
  network-spawned module must add itself to this group, or it leaks on
  disconnect. That's a contract callers (and the cleanup code) depend on.
