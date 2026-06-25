# Spam Email Filter (Bash + Regex) — `spam_filter.sh`

**CYBR 352 — Bash Scripting Project | Topic 03**

---

## 1. Overview

`spam_filter.sh` is an automated Bash spam email filter. It scans a directory of
`.eml` email files and classifies each one as **SPAM** or **HAM** (legitimate)
using a weighted scoring engine built on `grep` regular expressions.

The pipeline runs end-to-end with no user intervention after launch:

1. **Parse** — extracts the `From:` header, `Subject:` header, and message body
   from each `.eml` file.
2. **Score** — applies five independent regex-based checks:
   - Spam keyword matching (e.g., "win a prize", "click here", "free money") — +2 each
   - Blacklisted sender domains (e.g., `@spammer.com`, `@fakebank.net`) — +5
   - ALL-CAPS subject lines — +2
   - Excessive links in the body (more than 3 URLs) — +2
   - Large money amounts (e.g., `$1,000,000`) — +2
3. **Classify** — emails scoring at or above the threshold (default: 5) are SPAM.
4. **Report** — every verdict, score, and triggering reason is written to a
   dated log file (`spam_report_YYYY-MM-DD.log`) plus a final summary.
5. **Quarantine (optional)** — with `-q`, spam files are moved into
   `./quarantine/` automatically.

**Team Members:**
| Name | Student ID |
|------|------------|
| *Your Name* | *Your ID* |
| *Teammate 2 (optional)* | *ID* |

> ✏️ Replace the table above (and the header comment inside `spam_filter.sh`)
> with your real names and IDs before submitting.

---

## 2. Dependencies

The script only uses standard GNU/Linux core utilities — nothing exotic. All of
these are preinstalled on Kali Linux and Ubuntu:

| Tool | Purpose | Install (if missing) |
|------|---------|----------------------|
| `bash` (4.0+) | Script interpreter | `sudo apt install bash` |
| `grep` | Regex matching / scoring | `sudo apt install grep` |
| `awk` | Extracting the email body | `sudo apt install gawk` |
| `coreutils` (`date`, `basename`, `cut`, `wc`, `find`, `mv`, `mkdir`) | File ops & report naming | `sudo apt install coreutils` |
| `shellcheck` *(dev only)* | Static analysis before submission | `sudo apt install shellcheck` |

The script verifies its dependencies at startup via the `check_deps` function
and exits with a meaningful error if anything is missing.

---

## 3. Usage

Make the script executable, then run it:

```bash
chmod +x spam_filter.sh
./spam_filter.sh [OPTIONS]
```

### Flags & Arguments

| Flag | Argument | Description | Default |
|------|----------|-------------|---------|
| `-d` | `DIR` | Directory containing `.eml` files to scan | `.` (current dir) |
| `-t` | `NUM` | Spam score threshold (integer). Score ≥ threshold ⇒ SPAM | `5` |
| `-q` | — | Quarantine mode: move spam files to `./quarantine/` | off |
| `-h` | — | Show help and exit | — |

### Examples

```bash
# Scan the bundled test emails
./spam_filter.sh -d ./assets/test_data

# Stricter filter (higher threshold = fewer spam verdicts) + quarantine
./spam_filter.sh -d ./mail -t 7 -q

# Show help
./spam_filter.sh -h
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error (missing dependency, failed file move) |
| `2` | Misuse / bad input (bad directory, non-numeric threshold, no `.eml` files, unknown flag) |

---

## 4. Example Output

### Normal run (actual terminal output)

```
$ ./spam_filter.sh -d ./assets/test_data
[*] spam_filter.sh v1.0 — scanning './assets/test_data' (threshold: 5)

  [HAM ] ham_invoice.eml        score=0   (none)
  [HAM ] ham_meeting.eml        score=0   (none)
  [SPAM] spam_lottery.eml       score=25  (keyword:'click here' keyword:'free money' keyword:'limited time offer' keyword:'act now' keyword:'congratulations' keyword:'lottery' keyword:'wire transfer' blacklisted-domain:'@lottery-winner.info' all-caps-subject excessive-links:(4) money-amount )
  [SPAM] spam_phish.eml         score=11  (keyword:'click here' keyword:'urgent' keyword:'verify your account' blacklisted-domain:'@fakebank.net' )

=== Summary ===
Total scanned : 4
Spam detected : 2
Legit (ham)   : 2
Report saved  : spam_report_2026-06-11.log
```

### Error cases (actual terminal output — note: errors go to **stderr**)

```
$ ./spam_filter.sh -d /nonexistent
[ERROR] Mail directory not found: '/nonexistent'
$ echo $?
2

$ ./spam_filter.sh -d ./assets/test_data -t abc
[ERROR] Threshold '-t' must be a positive integer, got: 'abc'
$ echo $?
2

$ ./spam_filter.sh -d /tmp/emptydir
[ERROR] No .eml files found in '/tmp/emptydir'. Nothing to scan.
$ echo $?
2
```

### Quarantine mode

```
$ ./spam_filter.sh -d . -q
  ...
  [SPAM] spam_phish.eml         score=11  (keyword:'click here' ...)
         └─ moved to ./quarantine/

$ ls quarantine/
spam_lottery.eml  spam_phish.eml
```

---

## 5. Functions

| Function | What it does | Inputs | Outputs |
|----------|--------------|--------|---------|
| `usage` | Prints help text (flags, examples, exit codes) | none | help text → stdout |
| `check_deps` | Verifies required commands (`grep`, `awk`, `date`, …) exist via `command -v` | none | error → stderr + `exit 1` if missing |
| `validate_inputs` | Checks threshold is numeric, mail directory exists, and contains ≥1 `.eml` file | globals `$MAIL_DIR`, `$SPAM_THRESHOLD` | error → stderr + `exit 2` on failure |
| `score_email` | The scoring engine. Extracts Subject/From/body, runs all 5 regex checks, accumulates a weighted score | `$1` = path to `.eml` file | `"SCORE\|REASONS"` string → stdout |
| `process_email` | Calls `score_email`, classifies SPAM/HAM against the threshold, updates counters, logs to the report, quarantines if `-q` | `$1` = path to `.eml` file | verdict line → stdout, entry → report file |
| `generate_summary` | Prints final totals (scanned / spam / ham) to console and report | global counters | summary → stdout + report |
| `main` | Entry point: parses flags with `getopts` + `case`, runs validation, loops over all `.eml` files | `"$@"` (CLI args) | exit code 0/1/2 |

**Required constructs checklist:**

- `set -euo pipefail` header
- `for` loops
- `if`/`else` conditions
- `case` statement (flag parsing)
- Functions with `local` variables
- Input validation
- Dependency check
- Errors to stderr (`>&2`)
- 3+ distinct functional sections
- Passes `shellcheck` with no warnings

---

## 6. References

- **Bash Reference Manual** — https://www.gnu.org/software/bash/manual/
- `man bash`, `man grep`, `man awk`, `man getopts` — option parsing, regex syntax
- **ShellCheck** (static analysis) — https://www.shellcheck.net/
- **Google Shell Style Guide** — https://google.github.io/styleguide/shellguide.html
- **RFC 5322** (Internet Message Format — `.eml` header structure) — https://datatracker.ietf.org/doc/html/rfc5322
- **SpamAssassin rule concepts** (inspiration for weighted scoring) — https://spamassassin.apache.org/
- **OWASP** input validation principles — https://owasp.org/
- CYBR 352 Project Guideline (Summer 2026) — course handout

---

## Project Structure

```
CYBR352_Project_YourGroupName/
├── spam_filter.sh          # Main script
├── README.md               # This documentation
├── references.txt          # Reference list (plain text copy)
└── assets/
    └── test_data/
        ├── spam_lottery.eml   # Sample spam (lottery scam)
        ├── spam_phish.eml     # Sample spam (phishing)
        ├── ham_meeting.eml    # Sample legit email
        └── ham_invoice.eml    # Sample legit email
```

## Pre-Submission Checklist

```bash
bash -n spam_filter.sh        # Syntax check (passes)
shellcheck spam_filter.sh     # Static analysis (clean, 0 warnings)
chmod +x spam_filter.sh       # Executable bit set
./spam_filter.sh -d ./assets/test_data   # End-to-end test
```
