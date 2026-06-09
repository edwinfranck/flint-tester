#!/usr/bin/env bash
# =============================================================================
#  Flint (G-NSA-100) — Tester communautaire NON officiel
#  À lancer SUR la machine de l'étudiant (Arch ET Fedora, un boot à la fois).
#  Détecte l'OS courant et vérifie les points du barème, puis affiche un score.
#
#  Usage :   sudo ./flint_test.sh            (les deux OS auto-détectés)
#            sudo ./flint_test.sh arch       (forcer la section Arch)
#            sudo ./flint_test.sh fedora     (forcer la section Fedora)
#
#  [ OK ]  = critère validé automatiquement
#  [FAIL]  = critère non validé
#  [ ?? ]  = à VÉRIFIER MANUELLEMENT par le correcteur (le script affiche la valeur)
# =============================================================================

set -u

# ---- Re-exec en root (lecture de /etc/shadow, sshd_config, etc.) ------------
if [ "$(id -u)" -ne 0 ]; then
    echo ">> Élévation des privilèges nécessaire (sudo)..."
    exec sudo -E bash "$0" "$@"
fi

# ---- Couleurs ---------------------------------------------------------------
if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; C=$'\033[36m'; N=$'\033[0m'
else
    G=''; R=''; Y=''; B=''; C=''; N=''
fi

EARNED=0
MAX=0

addf() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%g", a+b}'; }

ok()  { EARNED=$(addf "$EARNED" "$2"); MAX=$(addf "$MAX" "$2");
        printf "  ${G}[ OK ]${N} %-52s ${G}+%s${N}\n" "$1" "$2"; }
ko()  { MAX=$(addf "$MAX" "$2");
        printf "  ${R}[FAIL]${N} %-52s ${R}0/%s${N}\n" "$1" "$2"; }
man() { printf "  ${Y}[ ?? ]${N} %-52s ${Y}(%s)${N}\n" "$1" "$2"; }
info(){ printf "        ${C}%s${N}\n" "$1"; }
hdr() { printf "\n${B}== %s ==${N}\n" "$1"; }

# ---- Helpers de taille (en MiB) ---------------------------------------------
size_mib() {  # $1 = mountpoint -> taille du device sous-jacent, en MiB
    local src b
    src=$(findmnt -fno SOURCE "$1" 2>/dev/null)
    [ -z "$src" ] && { echo 0; return; }
    b=$(lsblk -bdno SIZE "$src" 2>/dev/null | head -1)
    [ -z "$b" ] && { echo 0; return; }
    echo $(( b / 1024 / 1024 ))
}
in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }  # actual lo hi

fmt_size() {  # $1 = taille en Mio, $2 = échelle (mb|gb)
    if [ "$2" = "mb" ]; then echo "${1} Mio"
    else awk -v m="$1" 'BEGIN{printf "%.1f Gio", m/1024}'; fi
}

# Vérifie une partition : label, mountpoint, borne basse, borne haute (MiB),
# points, et libellé "cible" affiché à l'étudiant.
check_part() {
    local label="$1" mp="$2" lo="$3" hi="$4" pts="$5" target="$6"
    local sz scale found
    sz=$(size_mib "$mp")
    if [ "$hi" -lt 1000 ]; then scale=mb; else scale=gb; fi
    found=$(fmt_size "$sz" "$scale")
    if [ "$sz" -eq 0 ]; then
        ko "$label" "$pts"; info "attendu : $target  |  trouvé : RIEN monté sur $mp"
    elif in_range "$sz" "$lo" "$hi"; then
        ok "$label" "$pts"; info "attendu : $target  |  trouvé : $found  ($mp)"
    else
        ko "$label" "$pts"; info "attendu : $target  |  trouvé : $found  ($mp)  -> À AJUSTER"
    fi
}

# ---- Utilisateurs / groupes -------------------------------------------------
user_exists()   { id "$1" >/dev/null 2>&1; }
user_haspass()  { # mot de passe défini (hash dans /etc/shadow)
    local h; h=$(getent shadow "$1" 2>/dev/null | cut -d: -f2)
    case "$h" in $'\x24'*) return 0;; *) return 1;; esac
}
in_group()      { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
has_sudo()      { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel'; }

# ---- SSH --------------------------------------------------------------------
sshd_effective() {  # affiche la config sshd effective (clé en $1)
    sshd -T 2>/dev/null | grep -i "^$1 " | awk '{print $2}' | head -1
}
sshd_raw_grep() {   # repli si sshd -T indisponible
    grep -rhiE "$1" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null \
        | grep -v '^\s*#' | head -1
}

check_ssh_server() {
    hdr "Serveur SSH"
    # Installé ?
    if command -v sshd >/dev/null 2>&1; then
        ok "Serveur SSH installé" 0.5
    else
        ko "Serveur SSH installé" 0.5
    fi
    # Port 42 ?
    local port; port=$(sshd_effective port)
    [ -z "$port" ] && port=$(sshd_raw_grep '^\s*port\s+' | awk '{print $2}')
    if [ "$port" = "42" ]; then
        ok "Port SSH = 42" 0.5
    else
        ko "Port SSH = 42 (trouvé : ${port:-non défini, défaut 22})" 0.5
    fi
    # Password désactivé + clé activée (1 pt)
    local pa pk; pa=$(sshd_effective passwordauthentication)
    pk=$(sshd_effective pubkeyauthentication)
    if [ "$pa" = "no" ] && [ "$pk" = "yes" ]; then
        ok "Mot de passe désactivé + clé activée" 1
    else
        ko "Mot de passe désactivé + clé activée (password=${pa:-?}, pubkey=${pk:-?})" 1
    fi
    info "Test réel depuis l'hôte : ssh -p 4242 -i ~/.ssh/flint pierre@127.0.0.1"
}

# ---- Locales (communs Arch/Fedora) -----------------------------------------
check_locales() {
    hdr "Locales (langue / clavier / fuseau)"
    local lang
    lang=$(grep -hE '^LANG=' /etc/locale.conf /etc/default/locale 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    [ -z "$lang" ] && lang="${LANG:-}"
    if printf '%s' "$lang" | grep -qiE '^en_'; then
        ok "Système en anglais (LANG=$lang)" 0.5
    else
        ko "Système en anglais (LANG=${lang:-non défini})" 0.5
    fi
    local keymap; keymap=$(grep -hE '^KEYMAP=' /etc/vconsole.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    man "Clavier en langue natale  -> KEYMAP=${keymap:-non défini}" "à valider"
    local tz; tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    [ -z "$tz" ] && tz=$(readlink -f /etc/localtime | sed 's#.*/zoneinfo/##')
    man "Fuseau horaire de l'étudiant -> $tz  ($(date '+%Z %z'))" "à valider"
}

# =============================================================================
#  SECTION ARCH LINUX
# =============================================================================
test_arch() {
    printf "\n${B}#############  ARCH LINUX  #############${N}\n"

    hdr "Partitionnement"
    check_part "Partition root" /     13000 17500 0.5 "15 Go  (accepté 13–17,5 Gio)"
    check_part "Partition home" /home  4300  6000 0.5 "5 Go  (accepté 4,3–6 Gio)"
    check_part "Partition boot" /boot   400   700 0.5 "512 Mo  (accepté 400–700 Mio)"
    local efimp=/boot/efi; [ -d /efi ] && findmnt /efi >/dev/null 2>&1 && efimp=/efi
    check_part "Partition EFI" "$efimp"  400  700 0.5 "512 Mo  (accepté 400–700 Mio)"
    local swapb; swapb=$(swapon --show=SIZE --bytes --noheadings 2>/dev/null | head -1)
    if [ -n "$swapb" ]; then
        local swapm=$(( swapb / 1024 / 1024 ))
        if in_range "$swapm" 1700 2400; then
            ok "Swap actif" 0.5; info "attendu : 2 Go (accepté 1,7–2,4 Gio)  |  trouvé : $(fmt_size "$swapm" gb)"
        else
            ko "Swap actif" 0.5; info "attendu : 2 Go (accepté 1,7–2,4 Gio)  |  trouvé : $(fmt_size "$swapm" gb)  -> À AJUSTER"
        fi
    else
        ko "Swap actif" 0.5; info "attendu : 2 Go  |  trouvé : AUCUN swap actif"
    fi

    hdr "Environnement graphique"
    local de_graph=1 de_heavy=1
    pacman -Qq 2>/dev/null | grep -qiE '^(xorg-server|xorg-xinit|wayland|weston|sway|hyprland|i3-wm|i3-gaps|bspwm|openbox|xfce4|mate|cinnamon|lxqt|lxde|enlightenment|qtile|awesome|dwm|labwc|river)$' && de_graph=0
    { [ -x /usr/bin/Xorg ] || [ -x /usr/bin/X ] || [ -x /usr/bin/Hyprland ] || [ -x /usr/bin/sway ]; } && de_graph=0
    if [ "$de_graph" -eq 0 ]; then ok "Environnement graphique installé" 1
    else ko "Environnement graphique installé" 1; fi
    pacman -Qq 2>/dev/null | grep -qiE '^(gnome-shell|gnome-session|plasma-desktop|plasma-meta|plasma-workspace)$' && de_heavy=0
    if [ "$de_heavy" -ne 0 ]; then ok "N'est ni Gnome ni KDE Plasma" 1
    else ko "N'est ni Gnome ni KDE Plasma (Gnome/KDE détecté)" 1; fi

    check_locales

    hdr "Groupes et utilisateurs"
    if user_exists pierre && user_haspass pierre; then ok "pierre existe + mot de passe" 0.5
    else ko "pierre existe + mot de passe" 0.5; fi
    if in_group pierre poche; then ok "pierre dans le groupe 'poche'" 1
    else ko "pierre dans le groupe 'poche'" 1; fi
    if user_exists kong && user_haspass kong; then ok "kong existe + mot de passe" 0.5
    else ko "kong existe + mot de passe" 0.5; fi
    if in_group kong strong; then ok "kong dans le groupe 'strong'" 1
    else ko "kong dans le groupe 'strong'" 1; fi

    check_ssh_server
}

# =============================================================================
#  SECTION FEDORA
# =============================================================================
test_fedora() {
    printf "\n${B}#############  FEDORA  #############${N}\n"

    hdr "Partitionnement (LVM attendu)"
    if command -v lvdisplay >/dev/null 2>&1 && lvdisplay 2>/dev/null | grep -q 'LV Path'; then
        info "LVM détecté (pvdisplay / lvdisplay OK)"
    else
        info "Attention : aucun volume LVM détecté (le barème attend du LVM)"
    fi
    check_part "Partition root" /     17000 23000 0.5 "20 Go  (accepté 17–23 Gio)"
    check_part "Partition home" /home  8500 12000 0.5 "10 Go  (accepté 8,5–12 Gio)"
    check_part "Partition boot" /boot   400   700 0.5 "512 Mo  (accepté 400–700 Mio)"
    local efimp=/boot/efi; [ -d /efi ] && findmnt /efi >/dev/null 2>&1 && efimp=/efi
    check_part "Partition EFI" "$efimp"  400  700 0.5 "512 Mo  (accepté 400–700 Mio)"

    check_locales

    hdr "Groupes et utilisateurs"
    if user_exists pierre && user_haspass pierre && has_sudo pierre; then
        ok "pierre existe + mot de passe + sudo" 1
    else
        ko "pierre existe + mot de passe + sudo" 1
    fi

    hdr "Paquets Cyber (0,5 pt chacun)"
    local pkgs=(openvpn nmap ffuf gobuster hashcat john hydra netcat)
    for p in "${pkgs[@]}"; do
        local found=1
        rpm -q "$p" >/dev/null 2>&1 && found=0
        # alias de commandes / noms de paquets alternatifs
        case "$p" in
            netcat) { command -v nc >/dev/null || command -v ncat >/dev/null || rpm -q nmap-ncat >/dev/null 2>&1; } && found=0;;
            john)   command -v john >/dev/null && found=0;;
            *)      command -v "$p" >/dev/null 2>&1 && found=0;;
        esac
        if [ "$found" -eq 0 ]; then ok "Paquet '$p' installé" 0.5
        else ko "Paquet '$p' installé" 0.5; fi
    done

    hdr "Home d'Arch monté dans Fedora"
    if findmnt /mnt/arch-home >/dev/null 2>&1 && ls /mnt/arch-home >/dev/null 2>&1; then
        ok "/mnt/arch-home accessible" 1
    else
        ko "/mnt/arch-home accessible" 1
    fi

    check_ssh_server
}

# =============================================================================
#  MAIN
# =============================================================================
. /etc/os-release 2>/dev/null || true
DETECTED="${ID:-inconnu}"

FORCE="${1:-}"
printf "${B}╔══════════════════════════════════════════════╗${N}\n"
printf "${B}║   Flint (G-NSA-100) — Tester non officiel    ║${N}\n"
printf "${B}╚══════════════════════════════════════════════╝${N}\n"
printf "OS détecté : ${C}%s${N}  (%s)\n" "$DETECTED" "${PRETTY_NAME:-?}"

case "${FORCE:-$DETECTED}" in
    arch|archlinux|arch_linux) test_arch ;;
    fedora)                    test_fedora ;;
    *)
        echo
        echo "${Y}OS non reconnu automatiquement.${N}"
        echo "Relance en forçant : sudo $0 arch   ou   sudo $0 fedora"
        exit 1
        ;;
esac

# ---- Score ------------------------------------------------------------------
printf "\n${B}──────────────────────────────────────────────${N}\n"
printf "${B}SCORE AUTOMATIQUE : %s / %s point(s)${N}\n" "$EARNED" "$MAX"
printf "${Y}Rappel : les lignes [ ?? ] et le Mandatory (snapshot + SSH depuis\n"
printf "l'extérieur), l'oral et les bonus restent à évaluer par le correcteur.${N}\n"
