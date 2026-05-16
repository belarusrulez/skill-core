# sc shared helpers — POSIX sh. Sourced by sc/search/action (the only CLI in this system).
# No `set -eu` here — the sourcing script owns that.

# ----- output helpers -----
sc_warn() { printf 'WARN: %s\n' "$*" >&2; }
sc_err()  { printf 'ERROR: %s\n' "$*" >&2; }

# ----- SQL escape (single → doubled) -----
sc_sql_esc() {
  sed "s/'/''/g"
}

# ----- expand leading ~ in a path -----
sc_expand_root() {
  case "$1" in
    "~")   printf "%s\n" "$HOME" ;;
    "~/"*) printf "%s/%s\n" "$HOME" "${1#~/}" ;;
    *)     printf "%s\n" "$1" ;;
  esac
}

# ----- parse_patterns: emit "<root>\t<pattern>" per line -----
# Skip blank lines and # comments. Default pattern = "*"; "re:" prefix = regex.
sc_parse_patterns() {
  if [ ! -f "$SC_PATTERNS" ]; then
    return 0
  fi
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    {
      sub(/\r$/, "")
      line = $0
      tab = index(line, "\t")
      if (tab > 0) {
        root = substr(line, 1, tab - 1)
        pat  = substr(line, tab + 1)
      } else {
        match(line, /[[:space:]]+/)
        if (RSTART > 0) {
          root = substr(line, 1, RSTART - 1)
          pat  = substr(line, RSTART + RLENGTH)
        } else {
          root = line; pat = ""
        }
      }
      sub(/^[[:space:]]+/, "", root); sub(/[[:space:]]+$/, "", root)
      sub(/^[[:space:]]+/, "", pat);  sub(/[[:space:]]+$/, "", pat)
      if (root == "") next
      if (pat  == "") pat = "*"
      printf "%s\t%s\n", root, pat
    }
  ' "$SC_PATTERNS"
}

# ----- discover_skills: emit absolute paths to skill DIRS (deduped, sorted) -----
sc_discover_skills() {
  tmp_raw=$(mktemp -t sc_disc.XXXXXX)
  : > "$tmp_raw"
  sc_parse_patterns | while IFS=$(printf '\t') read root pat; do
    [ -n "$root" ] || continue
    root_e=$(sc_expand_root "$root")
    if [ ! -d "$root_e" ]; then
      sc_warn "skipping root (not a directory): $root_e"
      continue
    fi
    case "$pat" in
      re:*)
        regex="${pat#re:}"
        find "$root_e" -type f -name SKILL.md 2>/dev/null | while read p; do
          d=$(dirname "$p")
          b=$(basename "$d")
          if printf "%s\n" "$b" | grep -E -q -- "$regex"; then printf "%s\n" "$d"; fi
        done
        ;;
      "*")
        find "$root_e" -type f -name SKILL.md 2>/dev/null | while read p; do
          printf "%s\n" "$(dirname "$p")"
        done
        ;;
      *)
        find "$root_e" -type f -name SKILL.md 2>/dev/null | while read p; do
          d=$(dirname "$p")
          b=$(basename "$d")
          # shellcheck disable=SC2254
          case "$b" in
            $pat) printf "%s\n" "$d" ;;
          esac
        done
        ;;
    esac
  done >> "$tmp_raw"
  sort -u "$tmp_raw"
  rm -f "$tmp_raw"
}

# ----- fm_field <key> <path>: emit frontmatter value (one line, trimmed, unquoted) -----
sc_fm_field() {
  awk -v key="$1" '
    BEGIN { in_fm = 0; seen_open = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else            { in_fm = 0; exit }
    }
    in_fm {
      kp = key ":"
      if (index($0, kp) == 1) {
        v = substr($0, length(kp) + 1)
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
        if (length(v) >= 2) {
          first = substr(v, 1, 1)
          last  = substr(v, length(v), 1)
          if ((first == "\"" && last == "\"") || (first == "'\''" && last == "'\''")) {
            v = substr(v, 2, length(v) - 2)
          }
        }
        print v
        exit
      }
    }
  ' "$2"
}

# ----- body_after_fm <path>: emit content after the closing `---` -----
sc_body_after_fm() {
  awk '
    BEGIN { seen_open = 0; past = 0 }
    {
      if (past) { print; next }
      if ($0 ~ /^---[[:space:]]*$/) {
        if (!seen_open) { seen_open = 1; next }
        else            { past = 1; next }
      }
      if (!seen_open) {
        past = 1
        print
      }
    }
  ' "$1"
}

# ----- has_frontmatter <path>: 0 if file has a frontmatter block, 1 otherwise -----
sc_has_frontmatter() {
  awk '
    BEGIN { seen_open = 0; ok = 1 }
    NR == 1 && /^---[[:space:]]*$/ { seen_open = 1; next }
    seen_open && /^---[[:space:]]*$/ { ok = 0; exit }
    END { exit ok }
  ' "$1"
}

# ----- name_from_dirname <dirname>: first '-' → ':' only, rest unchanged -----
# my-cool-tool → my:cool-tool ; foo → foo ; sc → sc
sc_name_from_dirname() {
  printf "%s\n" "$1" | awk '
    {
      i = index($0, "-")
      if (i == 0) print $0
      else        printf "%s:%s\n", substr($0, 1, i-1), substr($0, i+1)
    }
  '
}

# ----- json_escape: stdin → stdout, escape for JSON string value -----
sc_json_escape() {
  # backslash and double-quote escapes. Control chars left raw (we don't expect any).
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
