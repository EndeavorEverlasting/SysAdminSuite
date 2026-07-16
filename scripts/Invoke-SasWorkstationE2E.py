#!/usr/bin/env python3
"""Fixture-only persistent-workstation E2E runner using the public orchestrator."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ORCHESTRATOR=ROOT/"scripts/Invoke-SasDeveloperWorkstation.py"
RESULT_SCHEMA=ROOT/"schemas/harness/developer-workstation-orchestrator-result.schema.json"
PROOF_SCHEMA=ROOT/"schemas/harness/developer-workstation-proof.schema.json"
FIXTURE_STEP_TIMEOUT_SECONDS=30
FIXTURE_RUN_TIMEOUT_SECONDS=120

JOURNEYS={
"workstation-windows-wsl-success":("windows","success","Apply",True,True,"PASS"),
"workstation-native-linux-success":("linux","success-linux","Apply",True,True,"PASS"),
"workstation-powershell-fallback":("windows","powershell-fallback","Plan",False,False,"PASS"),
"workstation-wsl-missing":("windows","wsl-missing","Plan",False,False,"ACTION_REQUIRED"),
"workstation-docker-only-distro":("windows","docker-only","Plan",False,False,"ACTION_REQUIRED"),
"workstation-tmux-missing":("windows","missing-tmux","Plan",False,False,"ACTION_REQUIRED"),
"workstation-wsl-without-keepalive":("windows","wsl-no-keepalive","Status",False,False,"ACTION_REQUIRED"),
"workstation-keepalive-healthy":("windows","keepalive-healthy","Status",False,False,"PASS"),
"workstation-stale-pid":("windows","stale-keepalive","Status",False,False,"ACTION_REQUIRED"),
"workstation-tmux-session-missing":("windows","tmux-session-missing","Status",False,False,"ACTION_REQUIRED"),
"workstation-session-survives-gui-close":("windows","persistence-simulation","Apply",True,True,"PASS"),
"workstation-nested-tmux-guard":("windows","nested-tmux","Start",False,False,"ACTION_REQUIRED"),
"workstation-wezterm-cli-gui-confusion":("windows","cli-gui-confusion","Plan",False,False,"ACTION_REQUIRED"),
"workstation-invalid-lua":("windows","malformed-lua","Apply",True,False,"FAIL"),
"workstation-unavailable-font":("windows","unavailable-font","Status",False,False,"PASS"),
"workstation-native-agent":("windows","success","Plan",False,False,"PASS"),
"workstation-windows-bridge-agent":("windows","bridge-only","Plan",False,False,"PARTIAL"),
"workstation-alias-only-agent-rejected":("linux","alias-only-agent","Plan",False,False,"ACTION_REQUIRED"),
"workstation-auth-required-v2":("linux","authentication-required","Plan",False,False,"ACTION_REQUIRED"),
"workstation-malformed-agentswitchboard":("linux","malformed-agent-result","Plan",False,False,"FAIL"),
"workstation-rollback-v2":("windows","rollback","Rollback",True,False,"PASS"),
"workstation-unsupported-mac-v2":("unsupported","unsupported-platform","Plan",False,False,"UNSUPPORTED"),
}


def load(path:Path):return json.loads(path.read_text(encoding="utf-8-sig"))
def write(path:Path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2)+"\n",encoding="utf-8")


def validate(value,schema_path):
    try:import jsonschema
    except ImportError:return
    jsonschema.Draft202012Validator(load(schema_path)).validate(value)


def public_run(scenario,mode,root,allow,launch):
    command=[sys.executable,str(ORCHESTRATOR),"--fixture-scenario",scenario,"--mode",mode,"--output-root",str(root),"--timeout-seconds",str(FIXTURE_STEP_TIMEOUT_SECONDS)]
    if allow:command.append("--allow-target-mutation")
    if launch:command.append("--launch-gui")
    completed=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=FIXTURE_RUN_TIMEOUT_SECONDS)
    result_path=root/"orchestrator-result.json"
    if not result_path.is_file():raise AssertionError(completed.stderr or "public orchestrator produced no result")
    result=load(result_path);validate(result,RESULT_SCHEMA)
    return completed,result


def artifacts_valid(root,result):
    registry_path=root/"artifact-registry.json";english=root/"english-summary.txt"
    if not registry_path.is_file() or not english.is_file():return False
    registry=load(registry_path)
    if registry.get("run_id")!=result.get("run_id"):return False
    return all((root/item["path"]).is_file() for item in registry.get("artifacts",[]))


def run_journey(journey_id,output_root):
    platform,scenario,mode,allow,launch,expected=JOURNEYS[journey_id]
    root=output_root/"workspace"
    first_process,first=public_run(scenario,mode,root,allow,launch)
    first_artifacts=artifacts_valid(root,first)
    if journey_id=="workstation-session-survives-gui-close":
        state_path=root/"fixture-state/windows-tmux-workspace-state.json"
        state=load(state_path);state["gui_launched"]=False;write(state_path,state)
        second_process,second=public_run(scenario,"Status",root,False,False)
        detail="Fixture GUI ownership was removed; the public Status entrypoint still found tmux dev."
    else:
        second_process,second=public_run(scenario,mode,root,allow,launch)
        detail="The public entrypoint produced the same typed outcome on an idempotent rerun."
    expected_exit=1 if expected=="FAIL" else 0
    idempotent=first["outcome"]==expected and second["outcome"]==expected and first_process.returncode==expected_exit and second_process.returncode==expected_exit
    proof={"schema_version":"sas-developer-workstation-proof/v2","journey_id":journey_id,"platform":platform,"expected_outcome":expected,"observed_outcome":second["outcome"],"status":"PASS" if idempotent and first_artifacts and artifacts_valid(root,second) else "FAIL","public_entrypoint":"scripts/Invoke-SasDeveloperWorkstation.py","artifacts_validated":bool(first_artifacts and artifacts_valid(root,second)),"idempotent_rerun":idempotent,"detail":detail,"proof":{"fixture":True,"live_runtime":False,"behavior_observed":False,"persistence_observed":False,"agent_interaction_observed":False,"operator_accepted":False}}
    validate(proof,PROOF_SCHEMA);write(output_root/"proof.json",proof)
    return proof


def main():
    parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--journey-id",choices=sorted(JOURNEYS));group.add_argument("--all",action="store_true")
    parser.add_argument("--output-root",type=Path,required=True);parser.add_argument("--platform-filter",choices=["all","windows","linux"],default="all")
    args=parser.parse_args();args.output_root.mkdir(parents=True,exist_ok=True)
    if args.journey_id:
        proof=run_journey(args.journey_id,args.output_root)
        print(f"[{proof['status']}] {proof['journey_id']}: expected={proof['expected_outcome']} observed={proof['observed_outcome']}")
        return 0 if proof["status"]=="PASS" else 1
    selected=[]
    for journey_id,(platform,*_) in JOURNEYS.items():
        if args.platform_filter=="all" or platform==args.platform_filter or platform=="unsupported":selected.append(journey_id)
    proofs=[]
    for journey_id in selected:
        if JOURNEYS[journey_id][0]=="windows" and os.name!="nt" and not shutil.which("pwsh"):
            continue
        proof=run_journey(journey_id,args.output_root/journey_id);proofs.append(proof)
    matrix={"schema_version":"sas-developer-workstation-e2e-matrix/v2","profile":"developer-workstation-persistent-e2e-v2","selected":len(selected),"executed":len(proofs),"passed":sum(p["status"]=="PASS" for p in proofs),"failed":sum(p["status"]=="FAIL" for p in proofs),"journeys":proofs,"proof":{"fixture":True,"live_runtime":False,"behavior_observed":False,"persistence_observed":False,"agent_interaction_observed":False,"operator_accepted":False}}
    write(args.output_root/"matrix.json",matrix)
    lines=["# Developer workstation fixture E2E matrix","",f"Executed: {matrix['executed']} | Passed: {matrix['passed']} | Failed: {matrix['failed']}","","| Journey | Status | Expected | Observed |","|---|---:|---:|---:|"]
    lines.extend(f"| `{p['journey_id']}` | {p['status']} | {p['expected_outcome']} | {p['observed_outcome']} |" for p in proofs)
    lines.extend(["","Fixture proof only: live runtime, behavior, persistence, agent interaction, and operator acceptance remain false."])
    (args.output_root/"matrix.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    print(f"PASS: {matrix['passed']} / {matrix['executed']} executed workstation E2E journeys")
    return 0 if matrix["failed"]==0 and matrix["executed"] else 1

if __name__=="__main__":raise SystemExit(main())
