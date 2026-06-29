#!/bin/bash
# ──────────────────────────────────────────────────────────────
# spam_filter.sh — Spam Email Filter (Bash + Regex)
# CYBR 352 — Bash Scripting Project (Topic 03)
# Group 11
#
# Scans a directory of .eml files, scores each email against
# spam keywords, blacklisted domains, and suspicious patterns,
# then classifies it as SPAM or HAM, optionally quarantines
# spam, and writes a dated report.
# ──────────────────────────────────────────────────────────────

# REQUIRED HEADER — exit on error (-e), unset vars are errors (-u),
# and a pipeline fails if ANY command in it fails (-o pipefail)
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# SECTION 1: CONFIGURATION & GLOBALS
# ══════════════════════════════════════════════════════════════

SCRIPT_NAME="$(basename "$0")"
VERSION="1.0"

# Default settings (overridable via CLI flags — no hardcoded paths)
MAIL_DIR="."                              # directory containing .eml files
SPAM_THRESHOLD=5                          # score >= threshold => SPAM
QUARANTINE=false                          # move spam to quarantine dir?
QUARANTINE_DIR="./quarantine"
REPORT_FILE="spam_report_$(date +%F).log"

# Spam keyword list — each match adds points to the spam score
SPAM_KEYWORDS=(
  "win a prize"
  "click here"
  "free money"
  "urgent"
  "verify your account"
  "limited time offer"
  "act now"
  "congratulations"
  "lottery"
  "wire transfer"
  "100% free"
  "risk-free"
)

# Blacklisted sender domains — instant heavy penalty
SPAM_DOMAINS=(
  "@spammer.com"
  "@fakebank.net"
  "@free-prizes.biz"
  "@lottery-winner.info"
)

# Scoring weights
WEIGHT_KEYWORD=2        # per keyword hit
WEIGHT_DOMAIN=5         # blacklisted sender domain
WEIGHT_CAPS_SUBJECT=2   # subject is ALL CAPS
WEIGHT_EXCESS_LINKS=2   # more than 3 URLs in body
WEIGHT_MONEY_REGEX=2    # money amounts like $1,000,000

# Counters for the final summary
TOTAL_EMAILS=0
SPAM_COUNT=0
HAM_COUNT=0

# ══════════════════════════════════════════════════════════════
# SECTION 2: HELPERS — usage, dependency check, input validation
# ══════════════════════════════════════════════════════════════

# Print usage/help to stdout and exit
usage() {
  cat <<EOF
$SCRIPT_NAME v$VERSION — Spam Email Filter (Bash + Regex)

Usage: ./$SCRIPT_NAME [OPTIONS]

Options:
  -d DIR     Directory containing .eml files   (default: current dir)
  -t NUM     Spam score threshold              (default: $SPAM_THRESHOLD)
  -q         Quarantine: move spam emails to $QUARANTINE_DIR
  -h         Show this help message and exit

Examples:
  ./$SCRIPT_NAME -d ./assets/test_data
  ./$SCRIPT_NAME -d ./mail -t 7 -q

Exit codes: 0 = success | 1 = general error | 2 = misuse / bad input
EOF
}

# Verify all required external commands exist before running
check_deps() {
  local dep
  for dep in grep awk date basename mktemp; do
    if ! command -v "$dep" &>/dev/null; then
      echo "[ERROR] Missing dependency: '$dep'. Install it and retry." >&2
      exit 1
    fi
  done
}

# Validate that the mail directory exists and contains .eml files
validate_inputs() {
  # Threshold must be a positive integer
  if ! [[ "$SPAM_THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Threshold '-t' must be a positive integer, got: '$SPAM_THRESHOLD'" >&2
    exit 2
  fi

  # Directory must exist
  if [[ ! -d "$MAIL_DIR" ]]; then
    echo "[ERROR] Mail directory not found: '$MAIL_DIR'" >&2
    exit 2
  fi

  # Must contain at least one .eml file
  local count
  count=$(find "$MAIL_DIR" -maxdepth 1 -type f -name '*.eml' | wc -l)
  if [[ "$count" -eq 0 ]]; then
    echo "[ERROR] No .eml files found in '$MAIL_DIR'. Nothing to scan." >&2
    exit 2
  fi
}

# ══════════════════════════════════════════════════════════════
# SECTION 3: SCORING ENGINE — regex-based spam detection
# ══════════════════════════════════════════════════════════════

# score_email FILE
#   Reads one .eml file and prints "SCORE|REASONS" to stdout.
score_email() {
  local file="$1"
  local score=0
  local reasons=""
  local subject sender body keyword domain

  # Extract headers (case-insensitive) and body
  subject=$(grep -i -m1 '^Subject:' "$file" | cut -d':' -f2- || true)
  sender=$(grep -i -m1 '^From:' "$file" | cut -d':' -f2- || true)
  # Body = everything after the first blank line
  body=$(awk 'blank{print} /^[[:space:]]*$/{blank=1}' "$file")

  # ── Check 1: spam keywords in subject OR body (case-insensitive)
  for keyword in "${SPAM_KEYWORDS[@]}"; do
    if grep -qiE "$keyword" <<< "$subject $body"; then
      score=$((score + WEIGHT_KEYWORD))
      reasons+="keyword:'$keyword' "
    fi
  done

  # ── Check 2: blacklisted sender domain
  for domain in "${SPAM_DOMAINS[@]}"; do
    if grep -qiF "$domain" <<< "$sender"; then
      score=$((score + WEIGHT_DOMAIN))
      reasons+="blacklisted-domain:'$domain' "
    fi
  done

  # ── Check 3: ALL-CAPS subject (3+ consecutive capital words)
  if [[ "$subject" =~ ([A-Z]{2,}[[:space:]]+){2,}[A-Z]{2,} ]]; then
    score=$((score + WEIGHT_CAPS_SUBJECT))
    reasons+="all-caps-subject "
  fi

  # ── Check 4: excessive links (more than 3 URLs in body)
  local link_count
  link_count=$(grep -oiE 'https?://[^[:space:]]+' <<< "$body" | wc -l)
  if [[ "$link_count" -gt 3 ]]; then
    score=$((score + WEIGHT_EXCESS_LINKS))
    reasons+="excessive-links:($link_count) "
  fi

  # ── Check 5: big money amounts, e.g. $1,000,000 or $5000
  if grep -qE '\$[0-9]{1,3}(,[0-9]{3})+|\$[0-9]{4,}' <<< "$body"; then
    score=$((score + WEIGHT_MONEY_REGEX))
    reasons+="money-amount "
  fi

  echo "${score}|${reasons:-none}"
}

# ══════════════════════════════════════════════════════════════
# SECTION 4: PROCESSING PIPELINE — classify, quarantine, report
# ══════════════════════════════════════════════════════════════

# process_email FILE — score, classify, log, optionally quarantine
process_email() {
  local file="$1"
  local result score reasons verdict

  result=$(score_email "$file")
  score="${result%%|*}"
  reasons="${result#*|}"

  TOTAL_EMAILS=$((TOTAL_EMAILS + 1))

  if [[ "$score" -ge "$SPAM_THRESHOLD" ]]; then
    verdict="SPAM"
    SPAM_COUNT=$((SPAM_COUNT + 1))
  else
    verdict="HAM"
    HAM_COUNT=$((HAM_COUNT + 1))
  fi

  # Console output (stdout — informational)
  printf '  [%-4s] %-22s score=%-3s %s\n' \
    "$verdict" "$(basename "$file")" "$score" "($reasons)"

  # Append to report file
  {
    echo "File   : $(basename "$file")"
    echo "Verdict: $verdict (score: $score / threshold: $SPAM_THRESHOLD)"
    echo "Reasons: $reasons"
    echo "---"
  } >> "$REPORT_FILE"

  # Quarantine spam if requested
  if [[ "$verdict" == "SPAM" && "$QUARANTINE" == true ]]; then
    if ! mv "$file" "$QUARANTINE_DIR/"; then
      echo "[ERROR] Failed to quarantine '$file'" >&2
      exit 1
    fi
    echo "         └─ moved to $QUARANTINE_DIR/"
  fi
}

# Write the summary footer to console + report
generate_summary() {
  local summary
  summary=$(cat <<EOF

=== Summary ===
Total scanned : $TOTAL_EMAILS
Spam detected : $SPAM_COUNT
Legit (ham)   : $HAM_COUNT
Report saved  : $REPORT_FILE
EOF
)
  echo "$summary"
  echo "$summary" >> "$REPORT_FILE"
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════

main() {
  # ── Parse CLI flags using a case statement ──
  while getopts ":d:t:qh" opt; do
    case "$opt" in
      d) MAIL_DIR="$OPTARG" ;;
      t) SPAM_THRESHOLD="$OPTARG" ;;
      q) QUARANTINE=true ;;
      h) usage; exit 0 ;;
      :) echo "[ERROR] Option -$OPTARG requires an argument." >&2; usage >&2; exit 2 ;;
      \?) echo "[ERROR] Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
    esac
  done

  check_deps
  validate_inputs

  # Create quarantine dir only if needed
  if [[ "$QUARANTINE" == true ]]; then
    mkdir -p "$QUARANTINE_DIR" || {
      echo "[ERROR] Cannot create quarantine dir: $QUARANTINE_DIR" >&2
      exit 1
    }
  fi

  # Initialize report
  echo "=== Spam Filter Report — $(date) ===" > "$REPORT_FILE"
  echo "Scanning: $MAIL_DIR | threshold: $SPAM_THRESHOLD" >> "$REPORT_FILE"
  echo "---" >> "$REPORT_FILE"

  echo "[*] $SCRIPT_NAME v$VERSION — scanning '$MAIL_DIR' (threshold: $SPAM_THRESHOLD)"
  echo

  # ── Loop over every .eml file ──
  local email
  for email in "$MAIL_DIR"/*.eml; do
    # Safety: skip if glob didn't match (shouldn't happen after validation)
    [[ -f "$email" ]] || continue
    process_email "$email"
  done

  generate_summary
  exit 0
}

main "$@"
