# Source in interactive Bash. Changes only the prompt in the current shell.
[[ $- == *i* ]] || return 0
if [[ ! ${HOST_TOOLS_PROMPT_SAVED+x} ]]; then
  HOST_TOOLS_OLD_PS1=$PS1
  HOST_TOOLS_PROMPT_SAVED=1
fi
PS1='\[\e[38;5;141m\]\u@\h\[\e[0m\] \[\e[38;5;245m\]\w\[\e[0m\]\n\[\e[38;5;141m\]\$\[\e[0m\] '
host_prompt_off() {
  PS1=$HOST_TOOLS_OLD_PS1
  unset HOST_TOOLS_OLD_PS1 HOST_TOOLS_PROMPT_SAVED
  unset -f host_prompt_off
}
