#!/usr/bin/env bash
# =============================================================================
#  Flint (G-NSA-100) — Évaluation PASSED / NOT PASSED  (tester non officiel)
#
#  DUAL BOOT : à lancer sur Arch PUIS à rebooter et relancer sur Fedora.
#  Le script détecte l'OS courant et évalue uniquement sa partie du barème.
#
#  Usage :  sudo ./flint_test.sh           (OS auto-détecté)
#           sudo ./flint_test.sh arch      (forcer Arch)
#           sudo ./flint_test.sh fedora    (forcer Fedora)
# =============================================================================
set -u

if [ "$(id -u)" -ne 0 ]; then
    echo ">> Élévation des privilèges nécessaire (sudo)..."
    exec sudo bash "$0" "$@"
fi

OSARG=""
for a in "$@"; do
    case "$a" in arch|archlinux|arch_linux) OSARG=arch;; fedora) OSARG=fedora;; esac
done

if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; C=$'\033[36m'; N=$'\033[0m'
else G=''; R=''; Y=''; B=''; C=''; N=''; fi

PASS=0; FAIL=0
pass() { printf "  ${G}[  PASSED  ]${N} %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${R}[NOT PASSED]${N} %s\n" "$1"; FAIL=$((FAIL+1)); }
chk()  { printf "  ${Y}[À VÉRIFIER]${N} %s\n" "$1"; }
hdr()  { printf "\n${B}== %s ==${N}\n" "$1"; }
verdict() { if "$@"; then pass "$LBL"; else fail "$LBL"; fi; }

# ---- Helpers ----------------------------------------------------------------
size_mib() {
    local src b
    src=$(findmnt -fno SOURCE "$1" 2>/dev/null); [ -z "$src" ] && { echo 0; return; }
    b=$(lsblk -bdno SIZE "$src" 2>/dev/null | head -1); [ -z "$b" ] && { echo 0; return; }
    echo $(( b / 1024 / 1024 ))
}
in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
fmt_size() { if [ "$2" = mb ]; then echo "${1} Mio"
             else awk -v m="$1" 'BEGIN{printf "%.1f Gio", m/1024}'; fi; }

# Ligne avec comparaison : statut(ok|ko) label attendu trouvé
row() {
    if [ "$1" = ok ]; then
        printf "  ${G}[  PASSED  ]${N} %-22s ${C}attendu %-9s | trouvé %s${N}\n" "$2" "$3" "$4"; PASS=$((PASS+1))
    else
        printf "  ${R}[NOT PASSED]${N} %-22s ${C}attendu %-9s | trouvé %s${N}\n" "$2" "$3" "$4"; FAIL=$((FAIL+1))
    fi
}
# label mountpoint lo hi (MiB) attendu-affiché
part_row() {
    local sz scale found
    sz=$(size_mib "$2")
    if [ "$4" -lt 1000 ]; then scale=mb; else scale=gb; fi
    if [ "$sz" -eq 0 ]; then found="ABSENTE"; row ko "$1" "$5" "$found"; return; fi
    found=$(fmt_size "$sz" "$scale")
    if in_range "$sz" "$3" "$4"; then row ok "$1" "$5" "$found"; else row ko "$1" "$5" "$found"; fi
}
# Vue d'ensemble : nombre de partitions + schéma réel
part_overview() {
    local nparts nlvm
    nparts=$(lsblk -rno TYPE 2>/dev/null | grep -c '^part$')
    nlvm=$(lsblk -rno TYPE 2>/dev/null | grep -c '^lvm$')
    printf "  ${C}Partitions physiques détectées : %s${N}\n" "$nparts"
    [ "$nlvm" -gt 0 ] && printf "  ${C}Volumes logiques LVM détectés  : %s${N}\n" "$nlvm"
    printf "  ${C}Schéma réel du disque :${N}\n"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -vE 'loop|sr0' | sed 's/^/    /'
}

user_exists()  { id "$1" >/dev/null 2>&1; }
user_haspass() { local h; h=$(getent shadow "$1" 2>/dev/null | cut -d: -f2)
                 case "$h" in $'\x24'*) return 0;; *) return 1;; esac; }
in_group()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
has_sudo()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel'; }
sshd_eff()     { sshd -T 2>/dev/null | grep -i "^$1 " | awk '{print $2}' | head -1; }

lang_en() { local l
    l=$(grep -hE '^LANG=' /etc/locale.conf /etc/default/locale 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    [ -z "$l" ] && l="${LANG:-}"; printf '%s' "$l" | grep -qiE '^en_'; }

check_locales() {
    hdr "Locales"
    LBL="Système en anglais"; verdict lang_en
    local keymap tz
    keymap=$(grep -hE '^KEYMAP=' /etc/vconsole.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    tz=$(timedatectl show -p Timezone --value 2>/dev/null); [ -z "$tz" ] && tz=$(readlink -f /etc/localtime | sed 's#.*/zoneinfo/##')
    chk "Clavier en langue natale   (KEYMAP=${keymap:-?})"
    chk "Fuseau horaire de l'étudiant   ($tz)"
}

check_ssh() {
    hdr "Serveur SSH"
    LBL="Serveur SSH installé"; verdict command -v sshd
    local port; port=$(sshd_eff port)
    LBL="Port SSH = 42"; if [ "$port" = "42" ]; then pass "$LBL"; else fail "$LBL"; fi
    local pa pk; pa=$(sshd_eff passwordauthentication); pk=$(sshd_eff pubkeyauthentication)
    LBL="Mot de passe désactivé + clé activée"
    if [ "$pa" = "no" ] && [ "$pk" = "yes" ]; then pass "$LBL"; else fail "$LBL"; fi
}

# =============================================================================
test_arch() {
    printf "\n${B}#############  ARCH LINUX  #############${N}\n"

    hdr "Partitionnement  (attendu : 5 partitions)"
    part_overview
    echo
    part_row "Partition root" /     13000 17500 "15 Go"
    part_row "Partition home" /home  4300  6000 "5 Go"
    part_row "Partition boot" /boot   400   700 "512 Mo"
    local efimp=/boot/efi; [ -d /efi ] && findmnt /efi >/dev/null 2>&1 && efimp=/efi
    part_row "Partition EFI" "$efimp"  400  700 "512 Mo"
    local swapb swapm; swapb=$(swapon --show=SIZE --bytes --noheadings 2>/dev/null | head -1)
    swapm=$(( ${swapb:-0} / 1024 / 1024 ))
    if [ "${swapb:-0}" -eq 0 ]; then row ko "Swap" "2 Go" "AUCUN"
    elif in_range "$swapm" 1700 2400; then row ok "Swap" "2 Go" "$(fmt_size "$swapm" gb)"
    else row ko "Swap" "2 Go" "$(fmt_size "$swapm" gb)"; fi

    hdr "Environnement graphique"
    local graph=1 heavy=1
    pacman -Qq 2>/dev/null | grep -qiE '^(xorg-server|xorg-xinit|wayland|weston|sway|hyprland|i3-wm|i3-gaps|bspwm|openbox|xfce4|mate|cinnamon|lxqt|lxde|enlightenment|qtile|awesome|dwm|labwc|river)$' && graph=0
    { [ -x /usr/bin/Xorg ] || [ -x /usr/bin/X ] || [ -x /usr/bin/Hyprland ] || [ -x /usr/bin/sway ]; } && graph=0
    LBL="Environnement graphique installé"; if [ "$graph" -eq 0 ]; then pass "$LBL"; else fail "$LBL"; fi
    pacman -Qq 2>/dev/null | grep -qiE '^(gnome-shell|gnome-session|plasma-desktop|plasma-meta|plasma-workspace)$' && heavy=0
    LBL="N'est ni Gnome ni KDE Plasma"; if [ "$heavy" -ne 0 ]; then pass "$LBL"; else fail "$LBL"; fi

    check_locales

    hdr "Groupes et utilisateurs"
    LBL="pierre existe + mot de passe"; if user_exists pierre && user_haspass pierre; then pass "$LBL"; else fail "$LBL"; fi
    LBL="pierre dans le groupe 'poche'"; verdict in_group pierre poche
    LBL="kong existe + mot de passe";   if user_exists kong && user_haspass kong; then pass "$LBL"; else fail "$LBL"; fi
    LBL="kong dans le groupe 'strong'"; verdict in_group kong strong

    check_ssh
}

test_fedora() {
    printf "\n${B}#############  FEDORA  #############${N}\n"

    hdr "Partitionnement LVM  (attendu : 4 partitions/volumes)"
    part_overview
    echo
    part_row "Volume root" /     17000 23000 "20 Go"
    part_row "Volume home" /home  8500 12000 "10 Go"
    part_row "Partition boot" /boot 400   700 "512 Mo"
    local efimp=/boot/efi; [ -d /efi ] && findmnt /efi >/dev/null 2>&1 && efimp=/efi
    part_row "Partition EFI" "$efimp" 400  700 "512 Mo"

    check_locales

    hdr "Groupes et utilisateurs"
    LBL="pierre existe + mot de passe + sudo"
    if user_exists pierre && user_haspass pierre && has_sudo pierre; then pass "$LBL"; else fail "$LBL"; fi

    hdr "Paquets Cyber"
    local p found
    for p in openvpn nmap ffuf gobuster hashcat john hydra netcat; do
        found=1; rpm -q "$p" >/dev/null 2>&1 && found=0
        case "$p" in
            netcat) { command -v nc >/dev/null || command -v ncat >/dev/null || rpm -q nmap-ncat >/dev/null 2>&1; } && found=0;;
            *)      command -v "$p" >/dev/null 2>&1 && found=0;;
        esac
        LBL="Paquet $p"; if [ "$found" -eq 0 ]; then pass "$LBL"; else fail "$LBL"; fi
    done

    hdr "Home d'Arch dans Fedora"
    LBL="/mnt/arch-home accessible"
    if findmnt /mnt/arch-home >/dev/null 2>&1 && ls /mnt/arch-home >/dev/null 2>&1; then pass "$LBL"; else fail "$LBL"; fi

    check_ssh
}

# =============================================================================
. /etc/os-release 2>/dev/null || true
RUN="${OSARG:-${ID:-inconnu}}"
case "$RUN" in archlinux|arch_linux) RUN=arch;; esac

printf "${B}Flint (G-NSA-100) — Évaluation PASSED / NOT PASSED${N}\n"
printf "OS : ${C}%s${N}\n" "${PRETTY_NAME:-$RUN}"

case "$RUN" in
    arch)   test_arch ;;
    fedora) test_fedora ;;
    *) printf "\n${Y}OS non reconnu. Relance : sudo %s arch  ou  sudo %s fedora${N}\n" "$0" "$0"; exit 1 ;;
esac

printf "\n${B}── %s : %s PASSED / %s NOT PASSED ──${N}\n" "$RUN" "$PASS" "$FAIL"
other=fedora; [ "$RUN" = fedora ] && other=arch
printf "${Y}Dual boot : reboote sur '%s' et relance pour évaluer l'autre partie.${N}\n" "$other"
