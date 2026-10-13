#!/bin/bash
# gate: none it only prints a path; order_guard.sh and approve_order_break.sh
# source it, and it reads no approval file and writes nothing.
#
# inc-4320. Print the one fixed approval path for a bead, resolved from the
# password database, NEVER from $HOME. The order rule must fail closed unless
# Brian approves, and $HOME is writable by anyone who runs the build, so a path
# built from it lets a caller plant a matching approval and bypass him.
#
# Usage: tools/order_approval_path.sh <bead-id>  ->  <home>/.config/incursion/order-approvals/<bead>
set -uo pipefail

[ "$#" -eq 1 ] || { echo "usage: tools/order_approval_path.sh <bead-id>" >&2; exit 2; }

home="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')" || exit 2
printf '%s/.config/incursion/order-approvals/%s\n' "$home" "$1"
