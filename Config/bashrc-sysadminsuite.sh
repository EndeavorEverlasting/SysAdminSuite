# SysAdminSuite managed native-Linux shell fragment.
case ":$PATH:" in
  *":$HOME/.local/agent-switchboard/bin:"*) ;;
  *) export PATH="$HOME/.local/agent-switchboard/bin:$PATH" ;;
esac
export AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=0
sas_dev_tmux() {
  [[ -z ${TMUX:-} ]] || { printf 'Already inside tmux; use the current workspace.\n' >&2; return 2; }
  command tmux new-session -A -s dev
}
