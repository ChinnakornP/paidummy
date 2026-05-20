# Pai Dummy (ไพ่ดัมมี่)

Online Thai-style Dummy card game: an authoritative Go game server + a Flutter
client (Riverpod + Flame).

```
pai_dummy/
├── server/            # Go: Gin REST + WebSocket, pure rules engine, Postgres + Redis
├── paidummy/          # Flutter client (Riverpod state, Flame table)
└── docker-compose.yml # Postgres + Redis for local dev
```

## Run it

1. **Infra** (Postgres on :5440, Redis on :6390 — remapped to avoid clashes):

   ```sh
   docker compose up -d
   ```

2. **Server** (migrations auto-apply on boot; listens on :8887):

   ```sh
   cd server && make run        # or: go run ./cmd/server
   ```

3. **Client** (point it at the server):

   ```sh
   cd paidummy
   flutter run --dart-define=API_BASE=http://localhost:8887 \
               --dart-define=WS_BASE=ws://localhost:8887
   ```

   Enter a name, create a room, tap **＋ เพิ่มบอท** to seat an auto-player,
   then **พร้อม** — you can play solo against bots. (Or open a second instance
   for a human opponent.)

### Scoring & coins

Each round is scored by the pure engine (`ScoreRound`: meld points, Speto,
head-card bonus, knock multipliers, hand penalties) and accumulated per match.
When a player reaches the target score the match ends and **coins settle**:
every guest has a wallet (starts at 1000), each room has a `bet`
(`POST /rooms` `{"bet":n}`, default 100), and at match end every loser pays the
bet (clamped to their balance) to the winner — atomically in Postgres
(`db.SettleMatch`). The `match_result` event carries per-player score,
`coin_delta` and new `balance`; the client shows wallet pills, the stake
banner, and a settlement summary dialog.

### Bots

`server/internal/bot` is a server-side auto-player. `POST /api/v1/rooms/:id/bots`
`{"count":n}` seats `n` bots (each gets a real guest row so scores persist).
A bot satisfies the same `room.Sender` interface as a human socket, auto-readies,
and on its turn draws/melds/knocks/discards — move legality is delegated to the
real engine (`game.NewMeld`), so a bot can never make an illegal play.

## Test

```sh
cd server
go test ./...                                  # unit (engine ~96% covered)
make up && go test -tags=integration ./test/integration/   # full WS round + persistence + hand-privacy

cd ../paidummy
flutter analyze && flutter test                # clean + smoke test
```

## Architecture notes

- `server/internal/game` is a **pure** rules engine (stdlib only): deck, melds
  (runs/sets, Ace high/low, no wrap), Speto (2♣, Q♠), the four knock variants,
  scoring. Every tunable lives in `RuleSet` (`ruleset.go`) with `// TODO(spec)`
  markers where the public manual was ambiguous — change rules there, never in
  engine logic.
- `room` is the authoritative bridge: applies engine actions, persists round
  snapshots to Redis (reconnection) and finished rounds/matches to Postgres.
- `ws/view.go` projects state **per player** — other hands are exposed only as
  a count, so hand leakage is structurally impossible (asserted by the
  integration test).
- The Flutter client holds no game logic; `GameController` reduces server
  events into an immutable `GameView` that drives the Flame table.
