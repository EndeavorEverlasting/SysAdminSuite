# Cybernet-First Dashboard UI Plan

Date: 2026-06-24  
Branch: `feature/cybernet-first-dashboard-ui-2026-06` (from PR #65 head `985ca0a`)

## Problem

The dashboard exposed too many controls on first load: mode toggle, clear-all, drop/paste/sample/watch, live command-gen, tutorial controls, five panel tabs, and an auto-tour. Field techs need one obvious Cybernet survey path.

## Control inventory and classification

| Control | ID / location | Classification | New placement |
|---------|---------------|----------------|---------------|
| Log Mode | `#mode-toggle` | Advanced / legacy | Advanced → Review Evidence |
| Live (Command-Gen) | `#mode-toggle` | Advanced | Advanced → Generate Survey Commands |
| Clear All | `#clear-all-btn` | Dangerous | Load Evidence panel (near loaded evidence chips) |
| Drop zone | `#drop-zone` | Secondary evidence | Load Evidence panel |
| Paste / Type | `#paste-btn` | Secondary evidence | Load Evidence panel |
| Load Sample Data | `#demo-btn` | Developer/demo | Advanced inside evidence loader |
| Watch Folder | `#watch-folder-btn` | Advanced | Advanced inside evidence loader |
| Stop Watch | `#watch-stop-btn` | Advanced | Advanced inside evidence loader |
| Live targets + Import | `#live-controls` | Advanced | Advanced → Generate Survey Commands |
| Generate Probe Commands | `#live-start` | Advanced | Advanced → Generate Survey Commands |
| Start Cybernet Survey | `#hero-start-survey` | Primary Cybernet | Hero primary CTA |
| Load Evidence | `#hero-load-evidence` | Secondary evidence | Hero + wizard footer |
| Open Advanced Tools | `#hero-open-advanced` | Secondary | Hero link → `#advanced-section` |
| Advanced Tools toggle | `#advanced-tools-toggle` | Secondary | Header button |
| Copy Command | `#cybernet-copy` | Wizard action | Wizard nav (when command exists) |
| Progress rail (×5) | `#cybernet-progress-rail` | Wizard chrome | Passive labels (non-clickable) |
| Review Results | `#cybernet-review` | Primary review | Visible after evidence loaded |
| Back / Next | `#cybernet-prev/next` | Wizard action | Wizard nav (secondary Back) |
| Panel tabs (×5) | `#tabs` | Advanced review | Advanced Review Panels |
| Relay badge | `#header-relay-badge` | Status | Header (unchanged) |
| Auto-tour | `tour.js` | Developer/demo | Suppressed on first load; Advanced only |

## First-screen button budget

Maximum **3** actionable controls on first load:

1. **Start Cybernet Survey** (primary)
2. **Load Evidence** (secondary)
3. **Advanced Tools** (secondary — toggles collapsed advanced section)

## Label mapping

| Old label | New label | Notes |
|-----------|-----------|-------|
| Log Mode | Review Evidence | Task language |
| Live (Command-Gen) | Generate Survey Commands | Hidden behind Advanced |
| Generate Probe Commands | Generate Survey Commands | Same capability |
| Start tutorial / Start Cybernet Survey | Start Cybernet Survey | Hero primary CTA (`#hero-start-survey`) |
| Copy current command | Copy Command | Wizard only when command exists (`#cybernet-copy`) |
| Live Mode (front door) | *(removed from first screen)* | Advanced → Generate Survey Commands only |
| Network & Protocol Trace | Network & Protocol (advanced) | Tab demoted |
| Naabu / keyports | Optional reachability check | Wizard step 4; profile in details |

**Avoid on first screen:** Live Mode, Command-Gen, Protocol Trace, Naabu, Parser, Manifest ingestion.

## Layout regions

```
Header: SysAdminSuite | relay | Advanced Tools
Hero: Cybernet Survey + progress rail + 3 CTAs (Start / Load Evidence / Open Advanced Tools)
Wizard: hidden until Start Cybernet Survey; one step at a time; rail = Targets → Network posture → Identity evidence → Reachability → Review package
Evidence loader: hidden until Load Evidence (hero, wizard footer, or end-of-wizard CTA)
Review Results (#cybernet-review): visible after recognized evidence is loaded
Advanced (collapsed): Review Evidence / Generate Survey Commands, ingestion extras, panel tabs
```

## What moved and why

- **Mode toggle** moved to Advanced so techs are not asked to pick Log vs Live before starting a survey.
- **Ingestion methods** consolidated under Load Evidence so one entry point covers drop, browse, and paste.
- **Panel tabs** demoted to Advanced Review Panels; Cybernet review summary is the default review path.
- **Clear All** lives in the Load Evidence panel next to evidence chips to reduce accidental data loss from the first screen.
- **Tutorial** becomes a wizard triggered only by Start Cybernet Survey; step pills are passive progress, not navigation.

## Capabilities preserved

All parsers, panels, Live Mode command generation (including low-noise naabu from PR #65), sample data, folder watch, paste modal, relay, and PowerShell handoff remain reachable. No operational capability is removed.

## Unsupported import claims

The normalized `cybernet_targets.csv` from `sas-survey-targets.sh` is **not** claimed as dashboard-importable until manifest parser support lands (PR #54). Wizard step 5 directs users to load recognized evidence CSVs only.

## Interactive tour (Cybernet-first)

The dashboard tour (`dashboard/js/tour.js`) follows the Cybernet-first DOM: hero CTA, progress rail, load evidence, review results, advanced tools, and status footer. Auto-launch is suppressed on first load (`sas_tour_v1_done` set in `app.js` before `initTour()`); relaunch via **Interactive tour** inside Advanced Tools or the `?` shortcut.
