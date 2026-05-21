# Pai Dummy — Roadmap / TODO

Living list of systems still to build. Ordered roughly by impact-to-effort
inside each theme. Effort scale: **XS** ≈ <½ day · **S** ≈ 1–2 days ·
**M** ≈ 3–5 days · **L** ≈ 1–2 weeks.

> Updated: 2026-05-20
>
> ✅ = shipped in the current branch (see commit log).

---

## ⭐ Top 5 priorities (if doing only five)

1. **In-room chat** (§1.1) — fastest win, button already exists, big
   retention pull.
2. **Sound effects + card animations** (§4.1 + §4.2) — closes the gap
   between "demo" and "real game".
3. **Rematch + reconnect mid-round** (§2.1 + §3.1) — biggest "this
   game frustrates me" gaps today.
4. **Daily bonus + missions** (§5.1 + §5.2) — cheap to build, large
   day-2 retention effect.
5. **Tutorial / onboarding** (§2.3) — Thai-Dummy rules trip up
   first-time players; the funnel leaks here.

---

## 1. Social & retention

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| ✅ 1.1 | In-room text chat + emoji react | Decorative chat button already in `_ChatButton`; server routes per-room broadcasts — needs only a `"chat"` WS message + a panel. | S |
| 1.2 | Friend list + private invite | Quickplay finds strangers; friends finish more rounds together. New `friends` / `invites` DB tables + REST + lobby sheet. | M |
| ✅ 1.3 | Private / password rooms | Hosting a session for a specific group. Add `password` to room create; gate Join. | S |
| 1.4 | Spectator mode | View-only seat. Reuse `room_state` but with `your_hand: []`; gate action handlers. | M |
| ✅ 1.5 | Player profile screen | Tap any seat → stats, history, rank. Pure read-side; reuses `MeHandler` + `MatchHistory`. | S |

## 2. Game flow polish

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| ✅ 2.1 | Rematch button after match end | Currently match ends → back to lobby. Keep players seated with a `rematch` WS message. | S |
| ✅ 2.2 | Room settings (target score / turn timer / dark-knock toggle) | Currently fixed in `DefaultRuleSet`. Surface a few knobs on room create. | S |
| 2.3 | Interactive tutorial / onboarding | First-time guest goes through a guided 3-turn demo against a bot. | M |
| ✅ 2.4 | Practice mode vs bots (no stake) | Solo training; reuses bot infra, just a room kind that doesn't settle coins. | S |
| ✅ 2.5 | "ช่วยคิด" / Suggest-a-move | When stuck, surface one suggested meld / layoff / discard. Extend the auto-knock solver. | M |

## 3. Robustness & fairness

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| 3.1 | Reconnect mid-round | Network drops happen. Server already persists state in Redis; needs a client "reconnecting…" overlay + auto-resume. | M |
| ✅ 3.2 | Disconnect protection (bot takeover) | Today the shot clock auto-discards once but the seat keeps stalling. A "play out as bot" toggle smooths real games. | S |
| 3.3 | Replay / move log viewer | Stored event stream per match (already partly in `db.SaveRound`). Add a scrubbable viewer dialog. | L |
| 3.4 | Report player + admin tools | One report button per seat + a small admin endpoint to mute/ban. | M |
| 3.5 | Anti-collusion heuristics | Background job tracking suspicious patterns (always loses to same player, always picks dummy from same player). | L |

## 4. Audio / visual / "feel"

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| ✅ 4.1 | Sound effects + ambient music | Card flip, deal, ทิ้ง, น็อค, win/lose stings. Asset pack + a Riverpod sound service. Single biggest "this feels like a game" upgrade. (SoundService + empty placeholder assets shipped; drop real .mp3s in to enable.) | S |
| 4.2 | Card animations (deal, draw, discard, meld lay-down) | Flame already drives the table; animate cards between zones with `Tween`s. | M |
| ✅ 4.3 | Haptics on action | `HapticFeedback.lightImpact()` on draw/meld/discard. Trivial. | XS |
| 4.4 | Card / table themes | Cosmetic-shop unlocks. Server stores `selected_skin` per guest; client renders accordingly. | M |
| ✅ 4.5 | Avatar picker (preset images) | 12 preset avatars makes the lobby read social. Today it's just a first-letter circle. | S |

## 5. Progression & monetisation

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| ✅ 5.1 | Daily login bonus + streak | Free coin every 24 h, scaling on consecutive days. `last_claim_at` column + one endpoint. | XS |
| ✅ 5.2 | Daily missions ("เล่น 3 ตา", "น็อคซ้ำสี") | Drives session length. Server-side mission set + progress writes on each match. | M |
| ✅ 5.3 | Leaderboards (daily / weekly / all-time) | Read-only ranking by coins won / matches won. SQL view + a lobby sheet. | S |
| 5.4 | Tournaments / scheduled events | One-shot rooms with prize pool ("ห้อง VIP ทุกวันศุกร์ 20:00"). | L |
| 5.5 | Watch-ad-for-coins | Optional sink — pair with a real ad SDK later, mock now. | M |
| ✅ 5.6 | Referral bonus | `?ref=<id>` deep link → both parties get coins on the friend's first match. | S |

## 6. Platform / operational

| # | Feature | Why | Effort |
| --- | --- | --- | --- |
| 6.1 | Push notifications | "ตาคุณแล้ว!" when the room is waiting on you. Needs FCM/APNs + a notification token table. | M |
| 6.2 | English (and other Thai dialect) localisation | Broader audience. `intl` package, `arb` files. Strings already centralised in `ui.dart`. | M |
| 6.3 | Real payment integration (replace mock) | Shop is mock today. PromptPay / TrueMoney / Apple-Google IAP. `PurchasePackage` already exists — wire a provider behind it. | L |
| 6.4 | Crash reporting + analytics | Sentry/Crashlytics + a small event pipeline (action counts, funnel drop-offs). | S |
| 6.5 | Admin dashboard | Read-only web view of rooms, player counts, recent rounds, support tickets. | M |

## 7. Long-shot / strategic

- Mobile-native shell (TestFlight / Play Store internal) — Flutter
  project already configured for mobile; store-review unlocks real-world
  traffic.
- Variant rules engine — Thai Dummy has many house variants (Hong Kong,
  4-deck). `RuleSet` is centralised; add room-level overrides.
- AI difficulty levels — current bots are basic; ladder-style
  ง่าย / ปานกลาง / ยาก for practice. Auto-knock solver can seed harder
  bots.
- Cross-platform profile sync — Sign-in with Google / Apple + recover
  wallet from any device. Today it's guest-only.

---

## ✅ Already shipped (for context)

- Pure rules engine (deal, draw deck, เก็บ multi-card pickup, meld,
  layoff, knock, discard) + auto-knock solver.
- Server-managed quickplay matchmaking with bet tiers + live per-tier
  player / room counts.
- Coin wallet with mock shop, coin history, room history.
- Rank ladder (ยศ) based on matches won.
- ทิ้งเต็ม / ทิ้งดัมมี่ penalties + ฝากดัมมี่ pickup-into-layoff path.
- Quadrant meld layout (A / B / C / D); self pinned at bottom-left.
- Rich round-end dialog (hands, melds, full score breakdown, coin
  delta).
- Bots, 45 s pre-start countdown, 60 s per-turn shot clock.
- Landscape lock + felt-themed home and lobby with horizontal-scroll
  portrait tier cards.
