# Host tools

For Ubuntu servers. Run `bash audit.sh` as root to gather a local, private report.
The audit does not install packages, refresh package indexes, restart services,
modify firewall rules, or collect environment variables and application configs.
Missing tools and failed commands are recorded with exit codes. Update results
depend on cached APT indexes; this inventory is not a comprehensive CVE scan.
Reports include service names, network addresses and firewall rules: review them
before sharing and do not commit them to a public repository.

To try a violet, two-line Bash prompt: `source prompt.sh`.
It lasts for the current shell; `host_prompt_off` restores the previous prompt.
No shell startup files are changed. Nothing requires a reboot.
