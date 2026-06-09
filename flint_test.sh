#!/usr/bin/env bash
# =============================================================================
#  Flint (G-NSA-100) — Tester communautaire NON officiel
#  À lancer SUR la machine de l'étudiant (Arch ET Fedora, un boot à la fois).
#  Détecte l'OS, vérifie les points du barème, et affiche TOUT dans le terminal :
#    - [ OK ] / [FAIL] / [ ?? ]   pour chaque critère
#    - la taille ATTENDUE vs TROUVÉE
#    - la COMMANDE pour corriger quand c'est raté
#    - les BONUS détectés
#    - un test SSH réel
#    - une FICHE DE NOTATION récapitulative + un score
#
#  Usage :
#    sudo ./flint_test.sh              # OS auto-détecté
#    sudo ./flint_test.sh arch         # forcer la section Arch
#    sudo ./flint_test.sh fedora       # forcer la section Fedora
#    sudo ./flint_test.sh -v           # mode preuve (affiche lsblk, id, sshd -T...)
# =============================================================================

set -u

# ---- Re-exec en root (lecture de /etc/shadow, sshd_config, etc.) ------------
if [ "$(id -u)" -ne 0 ]; then
    echo ">> Élévation des privilèges nécessaire (sudo)..."
    exec sudo -E bash "$0" "$@"
fi

# ---- Arguments --------------------------------------------------------------
VERBOSE=0
SCORE=0        # 0 = vue étudiant (PASSED / NOT PASSED) ; 1 = vue correcteur (points)
OSARG=""
for a in "$@"; do
    case "$a" in
        -v|--verbose) VERBOSE=1 ;;
        --score|--prof|--correcteur) SCORE=1 ;;
        arch|archlinux|arch_linux) OSARG="arch" ;;
        fedora) OSARG="fedora" ;;
    esac
done

# ---- Couleurs ---------------------------------------------------------------
if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; C=$'\033[36m'; M=$'\033[35m'; N=$'\033[0m'
else
    G=''; R=''; Y=''; B=''; C=''; M=''; N=''
fi

EARNED=0
MAX=0
SHEET=()   # lignes de la fiche récap : "STATUT|libellé|note"

addf() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%g", a+b}'; }

ok()  { EARNED=$(addf "$EARNED" "$2"); MAX=$(addf "$MAX" "$2")
        if [ "$SCORE" = 1 ]; then printf "  ${G}[ OK ]${N} %-52s ${G}+%s${N}\n" "$1" "$2"
        else printf "  ${G}[  PASSED  ]${N} %s\n" "$1"; fi
        SHEET+=("OK|$1|$2/$2"); }
# ko "libellé" points ["commande pour corriger"]
ko()  { MAX=$(addf "$MAX" "$2")
        if [ "$SCORE" = 1 ]; then printf "  ${R}[FAIL]${N} %-52s ${R}0/%s${N}\n" "$1" "$2"
        else printf "  ${R}[NOT PASSED]${N} %s\n" "$1"; fi
        [ -n "${3:-}" ] && printf "        ${M}→ corriger : %s${N}\n" "$3"
        SHEET+=("FAIL|$1|0/$2"); }
man() { printf "  ${Y}[À VÉRIFIER]${N} %-50s ${Y}(%s)${N}\n" "$1" "$2"
        SHEET+=("??|$1|$2"); }
info(){ printf "        ${C}%s${N}\n" "$1"; }
hdr() { printf "\n${B}== %s ==${N}\n" "$1"; }
# vrb "commande" : n'affiche la sortie QUE en mode -v
vrb() { [ "$VERBOSE" = 1 ] || return 0
        printf "        ${C}\$ %s${N}\n" "$1"
        eval "$1" 2>&1 | sed 's/^/          /'; }

# ---- Helpers de taille (en MiB) ---------------------------------------------
size_mib() {
    local src b
    src=$(findmnt -fno SOURCE "$1" 2>/dev/null)
    [ -z "$src" ] && { echo 0; return; }
    b=$(lsblk -bdno SIZE "$src" 2>/dev/null | head -1)
    [ -z "$b" ] && { echo 0; return; }
    echo $(( b / 1024 / 1024 ))
}
in_range() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
fmt_size() { if [ "$2" = "mb" ]; then echo "${1} Mio"
             else awk -v m="$1" 'BEGIN{printf "%.1f Gio", m/1024}'; fi; }

# label, mountpoint, lo, hi (MiB), points, cible-affichée
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
user_exists()  { id "$1" >/dev/null 2>&1; }
user_haspass() { local h; h=$(getent shadow "$1" 2>/dev/null | cut -d: -f2)
                 case "$h" in $'\x24'*) return 0;; *) return 1;; esac; }
in_group()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
has_sudo()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel'; }

# ---- SSH --------------------------------------------------------------------
OSID=""   # défini dans main
sshd_eff() { sshd -T 2>/dev/null | grep -i "^$1 " | awk '{print $2}' | head -1; }
sshd_raw() { grep -rhiE "$1" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null \
                 | grep -v '^\s*#' | head -1; }

real_ssh_test() {
    local key=""
    for k in ~/.ssh/flint /root/.ssh/flint ~/.ssh/id_rsa /root/.ssh/id_rsa; do
        [ -f "$k" ] && { key="$k"; break; }
    done
    if [ -z "$key" ]; then
        info "Test SSH réel ignoré : clé privée 'flint' absente sur cette machine."
        info "Le correcteur teste depuis SON poste : ssh -p 4242 -i ~/.ssh/flint pierre@<IP>"
        return
    fi
    if ssh -p 42 -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
           -i "$key" pierre@127.0.0.1 true 2>/dev/null; then
        info "Test SSH réel (port 42, clé $key) : ${G}CONNEXION RÉUSSIE ✅${N}${C}"
    else
        info "Test SSH réel (port 42) : échec (normal si cette clé n'est pas celle de pierre)"
    fi
}

check_ssh_server() {
    hdr "Serveur SSH"
    local inst_fix="sudo pacman -S openssh && sudo systemctl enable --now sshd"
    [ "$OSID" = "fedora" ] && inst_fix="sudo dnf install -y openssh-server && sudo systemctl enable --now sshd"
    if command -v sshd >/dev/null 2>&1; then ok "Serveur SSH installé" 0.5
    else ko "Serveur SSH installé" 0.5 "$inst_fix"; fi

    local port; port=$(sshd_eff port); [ -z "$port" ] && port=$(sshd_raw '^\s*port\s+' | awk '{print $2}')
    if [ "$port" = "42" ]; then ok "Port SSH = 42" 0.5
    else ko "Port SSH = 42 (trouvé : ${port:-22 par défaut})" 0.5 \
            "mettre 'Port 42' dans /etc/ssh/sshd_config puis: sudo systemctl restart sshd"; fi

    local pa pk; pa=$(sshd_eff passwordauthentication); pk=$(sshd_eff pubkeyauthentication)
    if [ "$pa" = "no" ] && [ "$pk" = "yes" ]; then ok "Mot de passe désactivé + clé activée" 1
    else ko "Mot de passe désactivé + clé activée (password=${pa:-?}, pubkey=${pk:-?})" 1 \
            "dans sshd_config : 'PasswordAuthentication no' et 'PubkeyAuthentication yes', puis restart sshd"; fi

    vrb "sshd -T | grep -Ei 'port|passwordauthentication|pubkeyauthentication'"
    real_ssh_test
}

# ---- Locales ----------------------------------------------------------------
check_locales() {
    hdr "Locales (langue / clavier / fuseau)"
    local lang
    lang=$(grep -hE '^LANG=' /etc/locale.conf /etc/default/locale 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    [ -z "$lang" ] && lang="${LANG:-}"
    if printf '%s' "$lang" | grep -qiE '^en_'; then ok "Système en anglais (LANG=$lang)" 0.5
    else ko "Système en anglais (LANG=${lang:-non défini})" 0.5 \
            "echo 'LANG=en_US.UTF-8' | sudo tee /etc/locale.conf  (puis régénérer les locales)"; fi
    local keymap; keymap=$(grep -hE '^KEYMAP=' /etc/vconsole.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    man "Clavier en langue natale  -> KEYMAP=${keymap:-non défini}" "à valider"
    local tz; tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    [ -z "$tz" ] && tz=$(readlink -f /etc/localtime | sed 's#.*/zoneinfo/##')
    man "Fuseau de l'étudiant -> $tz  ($(date '+%Z %z'))" "à valider"
    vrb "echo \$LANG; cat /etc/vconsole.conf 2>/dev/null; timedatectl | grep -i zone"
}

# ---- Bonus (informatif) -----------------------------------------------------
detect_bonus() {
    hdr "Bonus détectés (informatif — à valoriser par le correcteur)"
    local found=0
    if lsblk -o TYPE 2>/dev/null | grep -qi crypt; then
        info "🔒 Chiffrement de partition (LUKS) détecté"; found=1
    fi
    if command -v parrot-upgrade >/dev/null 2>&1 || grep -qi parrot /etc/os-release 2>/dev/null; then
        info "🦜 Environnement Parrot OS détecté"; found=1
    fi
    if pacman -Qq 2>/dev/null | grep -qiE '^(hyprland|i3-wm|i3-gaps|sway|bspwm|qtile|awesome|dwm)$' \
       || command -v neofetch >/dev/null 2>&1 || command -v fastfetch >/dev/null 2>&1; then
        info "🎨 Personnalisation / ricing probable (WM tuilant ou neofetch présent)"; found=1
    fi
    if command -v gentoo >/dev/null 2>&1 || grep -qi gentoo /etc/os-release 2>/dev/null; then
        info "🧱 Gentoo détecté"; found=1
    fi
    for tool in metasploit msfconsole burpsuite wireshark aircrack-ng; do
        command -v "$tool" >/dev/null 2>&1 && { info "🛠  Outil pentest présent : $tool"; found=1; }
    done
    [ "$found" -eq 0 ] && info "Aucun bonus auto-détecté (vérifie manuellement : pentest, perso, etc.)"
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
            ko "Swap actif" 0.5 "redimensionner le swap à ~2 Go"
            info "attendu : 2 Go (accepté 1,7–2,4 Gio)  |  trouvé : $(fmt_size "$swapm" gb)"
        fi
    else
        ko "Swap actif" 0.5 "créer un swap de 2 Go (mkswap + swapon + fstab)"
        info "attendu : 2 Go  |  trouvé : AUCUN swap actif"
    fi
    vrb "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; echo; df -h"

    hdr "Environnement graphique"
    local de_graph=1 de_heavy=1
    pacman -Qq 2>/dev/null | grep -qiE '^(xorg-server|xorg-xinit|wayland|weston|sway|hyprland|i3-wm|i3-gaps|bspwm|openbox|xfce4|mate|cinnamon|lxqt|lxde|enlightenment|qtile|awesome|dwm|labwc|river)$' && de_graph=0
    { [ -x /usr/bin/Xorg ] || [ -x /usr/bin/X ] || [ -x /usr/bin/Hyprland ] || [ -x /usr/bin/sway ]; } && de_graph=0
    if [ "$de_graph" -eq 0 ]; then ok "Environnement graphique installé" 1
    else ko "Environnement graphique installé" 1 "sudo pacman -S xorg-server + un WM (ex: i3-wm, xfce4...)"; fi
    pacman -Qq 2>/dev/null | grep -qiE '^(gnome-shell|gnome-session|plasma-desktop|plasma-meta|plasma-workspace)$' && de_heavy=0
    if [ "$de_heavy" -ne 0 ]; then ok "N'est ni Gnome ni KDE Plasma" 1
    else ko "N'est ni Gnome ni KDE Plasma (Gnome/KDE détecté)" 1 "installer un environnement plus léger que Gnome/KDE"; fi

    check_locales

    hdr "Groupes et utilisateurs"
    if user_exists pierre && user_haspass pierre; then ok "pierre existe + mot de passe" 0.5
    else ko "pierre existe + mot de passe" 0.5 "sudo useradd -m pierre && sudo passwd pierre"; fi
    if in_group pierre poche; then ok "pierre dans le groupe 'poche'" 1
    else ko "pierre dans le groupe 'poche'" 1 "sudo groupadd -f poche && sudo usermod -aG poche pierre"; fi
    if user_exists kong && user_haspass kong; then ok "kong existe + mot de passe" 0.5
    else ko "kong existe + mot de passe" 0.5 "sudo useradd -m kong && sudo passwd kong"; fi
    if in_group kong strong; then ok "kong dans le groupe 'strong'" 1
    else ko "kong dans le groupe 'strong'" 1 "sudo groupadd -f strong && sudo usermod -aG strong kong"; fi
    vrb "id pierre 2>/dev/null; id kong 2>/dev/null"

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
    vrb "pvdisplay 2>/dev/null; lvdisplay 2>/dev/null | grep -E 'LV Path|LV Size'; echo; lsblk; df -h"

    check_locales

    hdr "Groupes et utilisateurs"
    if user_exists pierre && user_haspass pierre && has_sudo pierre; then
        ok "pierre existe + mot de passe + sudo" 1
    else
        ko "pierre existe + mot de passe + sudo" 1 \
           "sudo useradd -m pierre && sudo passwd pierre && sudo usermod -aG wheel pierre"
    fi
    vrb "id pierre 2>/dev/null"

    hdr "Paquets Cyber (0,5 pt chacun)"
    local pkgs=(openvpn nmap ffuf gobuster hashcat john hydra netcat)
    for p in "${pkgs[@]}"; do
        local found=1
        rpm -q "$p" >/dev/null 2>&1 && found=0
        case "$p" in
            netcat) { command -v nc >/dev/null || command -v ncat >/dev/null || rpm -q nmap-ncat >/dev/null 2>&1; } && found=0;;
            *)      command -v "$p" >/dev/null 2>&1 && found=0;;
        esac
        if [ "$found" -eq 0 ]; then ok "Paquet '$p' installé" 0.5
        else ko "Paquet '$p' installé" 0.5 "sudo dnf install -y $p"; fi
    done

    hdr "Home d'Arch monté dans Fedora"
    if findmnt /mnt/arch-home >/dev/null 2>&1 && ls /mnt/arch-home >/dev/null 2>&1; then
        ok "/mnt/arch-home accessible" 1
    else
        ko "/mnt/arch-home accessible" 1 \
           "monter la partition home d'Arch sur /mnt/arch-home et l'ajouter à /etc/fstab"
    fi
    vrb "findmnt /mnt/arch-home; ls -la /mnt/arch-home 2>/dev/null"

    check_ssh_server
}

# =============================================================================
#  FICHE RÉCAP + SCORE + COMBINÉ
# =============================================================================
print_sheet() {
    local os="$1" line statut label note color
    local npass=0 nfail=0 ncheck=0

    if [ "$SCORE" = 1 ]; then
        # ----- Vue CORRECTEUR : fiche avec points + total -----
        printf "\n${B}════════════ FICHE DE NOTATION (%s) ════════════${N}\n" "$os"
        for line in "${SHEET[@]}"; do
            statut="${line%%|*}"; label="${line#*|}"; note="${label#*|}"; label="${label%%|*}"
            case "$statut" in
                OK)   color="$G"; statut="[ OK ]";;
                FAIL) color="$R"; statut="[FAIL]";;
                *)    color="$Y"; statut="[ ?? ]";;
            esac
            printf "${color}%-7s${N} %-46s ${color}%s${N}\n" "$statut" "$label" "$note"
        done
        printf "${B}─────────────────────────────────────────────────────${N}\n"
        printf "${B}TOTAL %s : %s / %s point(s) (auto)${N}\n" "$os" "$EARNED" "$MAX"
        return
    fi

    # ----- Vue ÉTUDIANT : juste ce qui passe / ce qui reste à corriger -----
    printf "\n${B}════════════ RÉCAPITULATIF (%s) ════════════${N}\n" "$os"
    local fails=()
    for line in "${SHEET[@]}"; do
        statut="${line%%|*}"; label="${line#*|}"; label="${label%%|*}"
        case "$statut" in
            OK)   npass=$((npass+1));;
            FAIL) nfail=$((nfail+1)); fails+=("$label");;
            *)    ncheck=$((ncheck+1));;
        esac
    done
    if [ "$nfail" -eq 0 ]; then
        printf "${G}${B}✅ Tout est PASSED pour %s !${N}\n" "$os"
    else
        printf "${R}${B}❌ À CORRIGER (%s) :${N}\n" "$os"
        for label in "${fails[@]}"; do printf "   ${R}• %s${N}\n" "$label"; done
    fi
    printf "${B}%s PASSED  /  %s NOT PASSED${N}" "$npass" "$nfail"
    [ "$ncheck" -gt 0 ] && printf "  ${Y}(+ %s à vérifier par le correcteur)${N}" "$ncheck"
    printf "\n"
}

# =============================================================================
#  MAIN
# =============================================================================
. /etc/os-release 2>/dev/null || true
DETECTED="${ID:-inconnu}"
RUN="${OSARG:-$DETECTED}"
case "$RUN" in archlinux|arch_linux) RUN=arch;; esac
OSID="$RUN"

printf "${B}╔══════════════════════════════════════════════╗${N}\n"
printf "${B}║   Flint (G-NSA-100) — Tester non officiel    ║${N}\n"
printf "${B}╚══════════════════════════════════════════════╝${N}\n"
printf "OS détecté : ${C}%s${N}  (%s)" "$DETECTED" "${PRETTY_NAME:-?}"
[ "$VERBOSE" = 1 ] && printf "   ${C}[mode preuve -v]${N}"
[ "$SCORE" = 1 ] && printf "   ${M}[mode correcteur]${N}"
printf "\n"

case "$RUN" in
    arch)   test_arch ;;
    fedora) test_fedora ;;
    *)  echo; echo "${Y}OS non reconnu. Relance : sudo $0 arch  ou  sudo $0 fedora${N}"; exit 1 ;;
esac

detect_bonus
print_sheet "$RUN"

# ---- Écriture d'un fichier résultat + total combiné Arch+Fedora -------------
DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || DIR="."
RESULT="$DIR/flint_result_${RUN}.txt"
{ print_sheet "$RUN"; } 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$RESULT"
printf "%s %s\n" "$EARNED" "$MAX" > "$DIR/.flint_score_${RUN}" 2>/dev/null
info "Fiche enregistrée dans : $RESULT"

a_file="$DIR/.flint_score_arch"; f_file="$DIR/.flint_score_fedora"
if [ "$SCORE" = 1 ] && [ -f "$a_file" ] && [ -f "$f_file" ]; then
    read -r ae am < "$a_file"; read -r fe fm < "$f_file"
    ge=$(addf "$ae" "$fe"); gm=$(addf "$am" "$fm")
    printf "\n${B}╞════════════ TOTAL COMBINÉ ARCH + FEDORA ════════════╡${N}\n"
    printf "${B}  Arch   : %s / %s${N}\n" "$ae" "$am"
    printf "${B}  Fedora : %s / %s${N}\n" "$fe" "$fm"
    printf "${B}  TOTAL  : %s / %s point(s) (parties auto-testables)${N}\n" "$ge" "$gm"
fi

# Rappel : ce projet est en DUAL BOOT -> il faut lancer le script sur les DEUX OS
other="fedora"; [ "$RUN" = "fedora" ] && other="arch"
printf "\n${Y}⚠  Projet DUAL BOOT : ce test ne couvre que la partie '%s'.\n" "$RUN"
printf "   Reboote sur '%s' et relance le script pour tester l'autre moitié du barème.${N}\n" "$other"
