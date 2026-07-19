# Resume Matcher — Workstation Deployment

Resume Matcher is a web application for tailoring resumes to job descriptions using LLM-powered analysis. It is deployed inside WSL Ubuntu and managed through the SysAdminSuite workstation tmux workspace.

## Architecture

| Layer | Stack | Port | Path (WSL) |
|-------|-------|------|------------|
| Backend | Python 3.13, FastAPI, Uvicorn, Playwright | 8000 | `/home/cheex/dev/Resume-Matcher/apps/backend` |
| Frontend | Next.js 16, Turbopack, TypeScript | 3000 | `/home/cheex/dev/Resume-Matcher/apps/frontend` |
| Database | SQLite | — | `apps/backend/data/resume_matcher.db` |
| Config | JSON | — | `apps/backend/data/config.json` |

Upstream source: `https://github.com/srbhr/Resume-Matcher.git`

## tmux Layout (session `dev`)

| Window | Name | Purpose |
|--------|------|---------|
| 0 | bash | General shell |
| 1 | rm-backend | Resume Matcher backend (Uvicorn on :8000) |
| 2 | bashrm-control | Control shell |
| 3 | rm-frontend | Frontend (Next.js on :3000) |
| 4 | sas-opencode | SysAdminSuite agent |
| 5 | sas-agy | SysAdminSuite agent |
| 6 | sas-goose | SysAdminSuite agent |

## Quick Start (CMD)

Double-click `scripts\Start-ResumeMatcher.cmd` — it starts both services and opens your browser to `http://localhost:3000`.

## How to Start

### Backend (already runs in tmux)
The backend is managed by the tmux `dev` session window `rm-backend`. To restart:

```bash
wsl -d Ubuntu -- bash -lc 'tmux send-keys -t dev:rm-backend "cd /home/cheex/dev/Resume-Matcher/apps/backend && uv run app" Enter'
```

### Frontend
```bash
wsl -d Ubuntu -- bash -lc 'tmux send-keys -t dev:0 "cd /home/cheex/dev/Resume-Matcher/apps/frontend && npm run dev" Enter'
```

The frontend starts on `http://localhost:3000` in ~1 second.

### Both at once
```bash
# Start backend
wsl -d Ubuntu -- bash -lc 'tmux send-keys -t dev:rm-backend "cd /home/cheex/dev/Resume-Matcher/apps/backend && uv run app" Enter'

# Start frontend
wsl -d Ubuntu -- bash -lc 'tmux send-keys -t dev:0 "cd /home/cheex/dev/Resume-Matcher/apps/frontend && npm run dev" Enter'
```

## How to Stop

Stop only the tmux session windows — do not kill processes by port or name:

```bash
# Stop frontend (send Ctrl+C to the window)
wsl -d Ubuntu -- bash -lc 'tmux send-keys -t dev:0 C-c'

# Or kill just the frontend tmux window
wsl -d Ubuntu -- bash -lc 'tmux kill-window -t dev:0'
```

## How to Verify

```bash
# Backend health
wsl -d Ubuntu -- bash -lc 'curl -s http://localhost:8000/'

# Frontend health
wsl -d Ubuntu -- bash -lc 'curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/'
# Expected: 200

# Port check
wsl -d Ubuntu -- bash -lc 'ss -tlnp | grep -E "8000|3000"'
```

## Configuration

### Backend `.env` (at `apps/backend/.env`)
| Variable | Default | Notes |
|----------|---------|-------|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8000` | Backend port |
| `LLM_PROVIDER` | `openai` | Overridden by `data/config.json` |
| `LLM_API_KEY` | — | Set via Settings UI in the frontend |

### `data/config.json`
Controls which LLM provider and model the backend uses. Currently configured for DeepSeek `deepseek-v4-flash`.

## Known State

- Backend is long-running (started Jul 15, managed by tmux).
- Frontend must be started manually after WSL restarts or tmux session recreation.
- No SysAdminSuite automation script exists yet for lifecycle management.
- PR #222 (`feat/workstation`) proposes full lifecycle automation but is not merged.

## Docker Alternative

Resume Matcher also supports Docker deployment:

```bash
cd /home/cheex/dev/Resume-Matcher
docker compose up -d    # Builds and starts on port 3000
docker compose down     # Stop
```

The Docker setup bundles both backend and frontend into a single container.
