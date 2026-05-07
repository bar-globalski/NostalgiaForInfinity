# CLAUDE.md

Guidance for Claude Code working in this repository. This is the user's **personal Freqtrade deployment**, forked from the NostalgiaForInfinity (NFI) strategy repo. The upstream repo ships the strategy + a Docker-based runtime; this fork uses it to run a real (currently dry-run) bot.

## Project context

- **Goal:** ~$200 educational crypto trading bot on Binance spot, mostly hands-off, high risk tolerance.
- **Bot:** Freqtrade in Docker, running NFI strategy (X7).
- **Mode:** **Dry run** (`dry_run: true`, `dry_run_wallet: 200`). No live keys configured. Do **not** enable `dry_run: false` or write API keys without explicit instruction.
- **Exchange:** Binance, **spot**, USDT pairs. (Upstream NFI is futures-by-default — this fork is overridden to spot.)
- **Sizing:** `max_open_trades: 8`, `stake_amount: 20`.
- **Bot identity:** `FREQTRADE__BOT_NAME=freqtrade-bar`. Container name: `freqtrade-bar_binance_spot-NostalgiaForInfinityX7`. API on `http://localhost:8080`.
- **Phase:** Local Windows dev box for setup/backtesting/hyperopt. Will deploy to a DigitalOcean droplet (Frankfurt/Amsterdam, Ubuntu 24.04) for 24/7 dry-run → live.

## How to run things

The bot runs in Docker via `docker-compose.yml`. Env comes from `.env` (gitignored). The strategy file is mounted via `${FREQTRADE__STRATEGY}.py` from repo root — the X7 strategy lives at `NostalgiaForInfinityX7.py` (top-level), not under `user_data/strategies/`.

```bash
docker compose up -d                # start bot
docker compose logs -f freqtrade    # tail logs
docker compose down                 # stop
docker compose ps                   # status
```

For one-off freqtrade subcommands, use `docker compose run --rm freqtrade <subcommand>`. Inside the container the workdir is `/freqtrade` and `user_data/` is bind-mounted.

### Windows / Git Bash gotcha

Git Bash on Windows rewrites absolute Unix paths in arguments (e.g. `/freqtrade/user_data/...` becomes `C:/Program Files/Git/freqtrade/user_data/...`) and breaks docker run commands. **Prefix any docker command that passes container-absolute paths with `MSYS_NO_PATHCONV=1`**, or use relative paths (cwd in the container is `/freqtrade`).

```bash
MSYS_NO_PATHCONV=1 docker compose run --rm freqtrade download-data --pairs-file /freqtrade/user_data/pairs-binance-spot-usdt.json ...
```

## Repo layout

```
NostalgiaForInfinityX7.py       # active strategy (mounted into container at root)
NostalgiaForInfinityX{1..6}.py  # historical strategy versions, kept for reference
user_data/strategies/sample_strategy.py  # Freqtrade boilerplate sample (not used)
configs/                        # upstream curated configs — DO NOT edit unless syncing
  exampleconfig.json            # base NFI config (timeframe=5m, max_open_trades=6, etc.)
  trading_mode-spot.json        # spot-mode overrides
  pairlist-volume-binance-usdt.json    # live pairlist (VolumePairList — top-N by volume)
  pairlist-backtest-static-binance-spot-usdt.json  # 160 static pairs for backtesting
  blacklist-binance.json
user_data/
  config.json                   # entry point — chains the configs/* files + private
  config-private.json           # gitignored, holds bot_name, dry_run wallet, sizing, keys
  data/binance/                 # downloaded OHLCV (gitignored)
  pairs-binance-spot-usdt.json  # flat pairs array for download-data (derived from pairlist)
  freqtrade-bar_binance_spot-tradesv3.sqlite  # bot's trade DB (gitignored)
  backtest_results/, hyperopt_results/, logs/, plot/, notebooks/
docker/Dockerfile.custom        # extends freqtradeorg/freqtrade:stable with test deps
docker-compose.yml              # main service def
```

`user_data/config.json` is intentionally minimal — it just chains the `configs/*` files via `add_config_files`. Per-deployment overrides live in `user_data/config-private.json` (sizing, dry-run, eventual API keys).

## Strategy notes (NFI X7)

- Base timeframe: **5m**. Informatives: **15m, 1h, 4h, 1d** (plus BTC info on the same set). Any data download must cover all five.
- README requires: `use_exit_signal=true`, `exit_profit_only=false`, `ignore_roi_if_entry_signal=true`, timeframe locked to 5m. Don't override these.
- Recommended pair count: 40–80. The current VolumePairList is fine for live; backtests use the 160-pair static list.
- The `nfi-updater` sidecar (defined in `docker-compose.yml`) auto-pulls strategy/blacklist/pairlist updates from upstream daily — **don't hand-edit `NostalgiaForInfinity*.py` or `configs/blacklist-*.json`**, your changes will be reverted.

## Common workflows

### Download historical OHLCV

```bash
MSYS_NO_PATHCONV=1 docker compose run --rm freqtrade download-data \
  --exchange binance --trading-mode spot \
  --pairs-file /freqtrade/user_data/pairs-binance-spot-usdt.json \
  --timeframes 5m 15m 1h 4h 1d \
  --days 180
  # NOTE: do NOT pass --datadir /freqtrade/user_data/data — that drops files flat
  # in user_data/data/ instead of user_data/data/binance/ where backtest expects them.
  # Default datadir resolves correctly. If you must pass it, use --datadir /freqtrade/user_data
  # so the per-exchange subdir is created.
```

`--pairs-file` expects a **flat JSON array** of pairs, not the `{exchange:{pair_whitelist:[...]}}` shape of the `configs/pairlist-*` files. `user_data/pairs-binance-spot-usdt.json` is the flattened version.

Verify what's downloaded:
```bash
ls user_data/data/binance/ | wc -l
MSYS_NO_PATHCONV=1 docker compose run --rm freqtrade list-data --exchange binance --trading-mode spot
```

### Backtest

```bash
MSYS_NO_PATHCONV=1 docker compose run --rm freqtrade backtesting \
  --strategy NostalgiaForInfinityX7 --strategy-path /freqtrade \
  --config /freqtrade/user_data/config.json \
  --timeframe 5m --timerange 20251101-20260501 \
  --datadir /freqtrade/user_data/data
```

Results land in `user_data/backtest_results/`. Do **not** invent timeranges — check what's actually downloaded first (`ls user_data/data/binance/`).

### View charts in the dashboard

FreqUI (the dashboard at `:8080`) does **not** show downloaded historical data as a standalone chart. To see history visually:

- **In FreqUI:** the **Chart** tab on the running bot pulls live OHLCV from the exchange, not from the downloaded files. Backtest runs can be loaded under the **Backtest** tab and visualized with entries/exits.
- **For raw history plots:** use `freqtrade plot-dataframe` / `plot-profit` — outputs go to `user_data/plot/*.html`, open in a browser.

## Conventions for working in this repo

- **Never** flip `dry_run` to `false`, never hard-code API keys, never push `.env` or `config-private.json` (already in `.gitignore`).
- **Don't edit** upstream NFI files (`NostalgiaForInfinityX*.py`, `configs/blacklist-binance.json`, `configs/pairlist-volume-binance-usdt.json`, `configs/exampleconfig.json`) — they're auto-synced from upstream. User overrides go in `user_data/config-private.json` or `.env`.
- **Custom strategies** live under `user_data/strategies/`, not at repo root. The mount in `docker-compose.yml` only exposes top-level strategies; if adding a custom one, mount it or move accordingly.
- **Git status:** `main` branch tracks user's fork. Recent commits (`X7: system_v3_2: …`) come from upstream NFI and are merged in periodically via the updater. Local commits should be in clearly separate branches/commits so upstream merges stay clean.
- **Container restart needed** after editing `NostalgiaForInfinityX7.py` or any file in `configs/` / `user_data/config*.json`: `docker compose restart freqtrade`.
- Check `docker compose ps` before assuming the bot is or isn't running — the user often has it up while iterating.
