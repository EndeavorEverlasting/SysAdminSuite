@echo off
title Resume Matcher
echo Starting Resume Matcher...

:: Start backend if not running
wsl -d Ubuntu -- bash -lc "ss -tlnp 2>/dev/null | grep -q :8000 || tmux send-keys -t dev:rm-backend 'cd /home/cheex/dev/Resume-Matcher/apps/backend ^&^& uv run app' Enter"

:: Start frontend
wsl -d Ubuntu -- bash -lc "tmux send-keys -t dev:0 'cd /home/cheex/dev/Resume-Matcher/apps/frontend ^&^& npm run dev' Enter"

:: Wait for frontend to be ready
echo Waiting for frontend on port 3000...
:wait
timeout /t 1 /nobreak >nul
wsl -d Ubuntu -- bash -lc "curl -sf http://localhost:3000/ >/dev/null 2>&1 && echo ready || echo notready" | findstr /c:"ready" >nul 2>&1
if errorlevel 1 goto wait

echo Resume Matcher is ready at http://localhost:3000
start http://localhost:3000
