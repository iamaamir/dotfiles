# shellcheck shell=sh
# git/lib/ticket.sh — single home of the ticket rule.
# POSIX sh + BSD/GNU grep: sourceable from both gptcommit.sh (bash) and the
# legacy prepare-commit-msg hook (sh). Keep it dependency-free.
#
# Canonical rule: the first [A-Z]{2,}-[0-9]+ key in the branch name.

# ticket_from_branch <branch-name>
# Print the ticket key, or nothing when the branch carries none.
# Pure: no git, no filesystem — the caller supplies the branch name
# (dependency injection), so tests drive this without a repo.
# Always exits 0: `|| true` shields the no-match exit (and SIGPIPE from
# head) so empty output never trips `set -e` in callers.
ticket_from_branch() {
  printf '%s' "${1:-}" | grep -o '[A-Z]\{2,\}-[0-9]\+' | head -n 1 || true
  return 0
}
