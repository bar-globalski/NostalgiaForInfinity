# Binance Live Integration Guide

Complete checklist to switch the droplet bot from dry-run to live trading on Binance USDⓈ-M Futures.

> **Assumption:** You already created a Binance API key (HMAC, "System generated") with permissions and IP whitelist set, and you have the **API Key** and **Secret** stored securely. If not, see [§ Appendix A — Creating the API key](#appendix-a--creating-the-api-key-from-scratch).

**Droplet IP:** `167.99.241.246` &nbsp;·&nbsp; **URL:** `https://vault-x7-fra.simplewords.co.il`

---

## 1. Required Binance account settings

Freqtrade verifies these on startup. Wrong values → bot refuses to start.

| Setting | Where | Required value |
|---|---|---|
| **Position Mode** | Binance Futures → top-right ⚙ Preferences → Position Mode | **One-way Mode** |
| **Asset Mode** | Same preferences panel | **Single-Asset Mode** |
| **Margin Mode** | Per-pair (NFI sets it via API) | **Isolated** (already in [.env](../.env): `FREQTRADE__MARGIN_MODE=isolated`) |

> **Quote — Freqtrade docs:** *"Users will also have to have the futures-setting 'Position Mode' set to 'One-way Mode', and 'Asset Mode' set to 'Single-Asset Mode'. These settings will be checked on startup."*

## 2. Fund the correct wallet

Binance separates wallets. **The bot can only see the USDⓈ-M Futures wallet.**

1. Buy/transfer USDT into your **Spot** wallet.
2. Go to **Wallet → Transfer → Spot to USDⓈ-M Futures**.
3. Move the amount you're willing to risk. **Start with the same amount you dry-tested** (e.g. $1000) for comparable results.
4. Your Spot holdings (BTC, ETH, etc.) stay untouched — the bot can't access them.

## 3. Sanity check before flipping

SSH in and run a no-money-at-risk verification with your live keys:

```bash
ssh freqtrade@167.99.241.246
cd freqtrade-nfi

# Temporarily export keys for the test command (does not modify .env)
export FREQTRADE__EXCHANGE__KEY="<your_api_key>"
export FREQTRADE__EXCHANGE__SECRET="<your_api_secret>"

# Hits Binance with your real keys — fails fast on bad permissions
docker compose exec freqtrade freqtrade test-pairlist
```

Expected: a printed whitelist of ~50–80 pairs. Any error here means a permission/IP/account-mode problem — fix before going live.

Also recommended (validates account access without placing orders):

```bash
docker compose exec freqtrade freqtrade show-trades --print-json | head
```

## 4. Inject keys into .env and go live

```bash
ssh freqtrade@167.99.241.246
cd freqtrade-nfi
nano .env
```

Edit exactly these three lines:

```env
FREQTRADE__EXCHANGE__KEY=<your_api_key>
FREQTRADE__EXCHANGE__SECRET=<your_api_secret>
FREQTRADE__DRY_RUN=false
```

Save, then restart:

```bash
docker compose restart freqtrade
docker compose logs -f freqtrade
```

In the live log, look for:

- `Using Exchange "Binance"`
- `Live trading enabled` (no longer "Dry-run")
- A real wallet balance matching your Binance Futures wallet
- No `Position Mode` / `Asset Mode` errors
- No `IP not whitelisted` errors

`Ctrl+C` to detach (the container keeps running).

## 5. First 24 hours — what to watch

| Check | Where | Why |
|---|---|---|
| Wallet balance matches Binance | FreqUI dashboard vs Binance Futures wallet | Confirms account access |
| First trade entry price matches Binance | FreqUI Trades vs Binance trade history | Confirms order pipeline |
| Position Mode shows "One-way" | Binance Futures positions panel | Confirms account setting honored |
| No "trading suspended" log lines | `docker compose logs freqtrade` | Confirms not hitting [Quantitative Rules](https://www.freqtrade.io/en/stable/exchanges/#binance) |
| Telegram/email alerts (if enabled) | Phone | Confirms notifications work |

## 6. Switching back to dry-run (always safe)

```bash
sed -i 's/^FREQTRADE__DRY_RUN=false/FREQTRADE__DRY_RUN=true/' .env
docker compose restart freqtrade
```

Open positions on Binance are **not** auto-closed by this. Close them manually on Binance first if you don't want them sitting there during the dry-run.

## 7. Killswitch

If anything looks wrong in live mode:

```bash
# Stop the bot immediately (does NOT close open positions)
sudo systemctl stop freqtrade.service

# Then close positions manually on Binance Futures UI
```

To close positions via the bot before stopping:

```bash
docker compose exec freqtrade freqtrade forceexit all
```

---

## Appendix A — Creating the API key from scratch

Skip if you already have your key.

### A.1 — Key type

Binance → Account → API Management → Create API → **System generated (HMAC)**.

> Ed25519 and RSA also work (CCXT ≥ 4.3.56 fixed Ed25519, our container runs CCXT 4.5.50). HMAC is simplest and the default for NFI users.

### A.2 — Permissions

Tick exactly these:

- ✅ **Enable Reading** *(required)*
- ✅ **Enable Spot & Margin Trading** *(needed for some balance calls even on a futures bot)*
- ✅ **Enable Futures** *(critical — bot trades USDⓈ-M futures)*
- ❌ **Enable Withdrawals** — **NEVER**. No reason a trading bot needs this. Difference between "lost trading capital" and "lost everything".
- ❌ Internal Transfer / Universal Transfer / Permits Universal Transfer / Vanilla Options — leave off.

### A.3 — IP whitelist

In the same key-creation flow:

- Choose **"Restrict access to trusted IPs only"**.
- Add: `167.99.241.246`
- Without IP whitelist Binance forces 90-day key expiration.

### A.4 — Save the secret

Binance shows the **Secret Key** exactly **once**. Copy it immediately into a password manager. If you lose it, you must regenerate the key.

---

## Appendix B — Required configuration recap

Already configured on the droplet — for reference.

| File | Value | Notes |
|---|---|---|
| `.env` | `FREQTRADE__EXCHANGE__NAME=binance` | Exchange |
| `.env` | `FREQTRADE__TRADING_MODE=futures` | Futures, not spot |
| `.env` | `FREQTRADE__MARGIN_MODE=isolated` | Per-pair isolated margin |
| `.env` | `FREQTRADE__STRATEGY=NostalgiaForInfinityX7` | Strategy name |
| [user_data/config.json](../user_data/config.json) | `dry_run_wallet: 1000` | Starting test wallet |
| [user_data/config.json](../user_data/config.json) | `max_open_trades: 6` | NFI-recommended |
| [user_data/config.json](../user_data/config.json) | `stake_amount: "unlimited"` | NFI requirement |
| [configs/blacklist-binance.json](../configs/blacklist-binance.json) | Includes `BNB/USDT:USDT` | Per Freqtrade docs — BNB consumed for fees |

## Appendix C — Key rotation

Rotate every 90 days, or immediately if you suspect a leak.

```bash
ssh freqtrade@167.99.241.246
cd freqtrade-nfi
nano .env       # paste new KEY + SECRET
docker compose restart freqtrade
```

Then disable the old key on Binance API Management (don't delete it until the new one is confirmed working).

## Appendix D — Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `APIError: Invalid API-key, IP, or permissions` | IP whitelist or permissions wrong | Verify droplet IP `167.99.241.246` is in the key's whitelist; verify Reading + Spot + Futures all enabled |
| `Position Mode is HEDGE not ONEWAY` | Binance account in Hedge Mode | Binance Futures → preferences → set to One-way Mode |
| `Asset Mode must be Single-Asset` | Account in Multi-Asset Mode | Binance Futures → preferences → set to Single-Asset Mode |
| `Trading suspended` in log | Hit Binance [Quantitative Rules](https://www.freqtrade.io/en/stable/exchanges/#binance) (too many low-fill orders) | Wait out the temporary ban (usually hours), no config change needed — NFI is tuned to stay under it |
| Live wallet ≠ Binance Futures wallet | Funds in wrong wallet | Spot → USDⓈ-M Futures transfer |
| Bot enters but never exits | Ran out of API rate budget for tickers | Check log for `Rate limit` warnings; reduce pairlist size |

## Sources

- [Freqtrade — Binance exchange-specific notes](https://www.freqtrade.io/en/stable/exchanges/#binance)
- [Freqtrade — Configuration reference](https://www.freqtrade.io/en/stable/configuration/)
- [Freqtrade GH#10397 — Ed25519 support](https://github.com/freqtrade/freqtrade/issues/10397)
- [Binance — API Key Types FAQ](https://developers.binance.com/docs/binance-spot-api-docs/faqs/api_key_types)
- [Binance — Ed25519 key pair generation](https://www.binance.com/en/support/faq/how-to-generate-an-ed25519-key-pair-to-send-api-requests-on-binance-6b9a63f1e3384cf48a2eedb82767a69a)
