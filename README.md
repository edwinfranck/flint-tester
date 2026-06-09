# Flint Tester (G-NSA-100) — tester communautaire

> ⚠️ **Tester NON officiel**, écrit pour remplacer le dépôt `tests-G-NSA-100-gamut`
> qui ne fonctionne pas. Il vous aide à **vérifier votre travail avant la soutenance**.
> Le correcteur garde le dernier mot : certaines lignes restent à évaluer à la main.

## À quoi ça sert

Le script `flint_test.sh` se lance **sur votre VM** (Arch **et** Fedora, un OS à la fois).
Il détecte automatiquement l'OS courant et vérifie les points du barème :
partitionnement, environnement graphique, locales, utilisateurs/groupes, serveur SSH,
paquets cyber (Fedora), home d'Arch monté dans Fedora… puis affiche un **score**.

## Utilisation

```bash
git clone https://github.com/edwinfranck/flint-tester.git
cd flint-tester
chmod +x flint_test.sh

# Sous Arch (booté sur Arch) :
sudo ./flint_test.sh

# Sous Fedora (booté sur Fedora) :
sudo ./flint_test.sh

# Mode preuve (affiche lsblk, df, id, sshd -T... sous chaque test) :
sudo ./flint_test.sh -v
```

> Le script se relance tout seul avec `sudo` (lecture de `/etc/shadow`, `sshd_config`…).
> Si l'OS n'est pas détecté, forcez la section :
> ```bash
> sudo ./flint_test.sh arch
> sudo ./flint_test.sh fedora
> ```

## ⚠ Projet DUAL BOOT : à lancer sur LES DEUX OS

Le barème a une partie **Arch** et une partie **Fedora**, testées chacune **depuis
l'OS concerné**. Le script détecte automatiquement où il tourne :

- booté sur **Arch** → il teste la partie **Arch** seulement
- rebooté sur **Fedora** → il teste la partie **Fedora** seulement

👉 Lance-le **une fois sur Arch, puis reboote et relance-le sur Fedora**.
Un seul OS ne couvre que la moitié du barème.

## Affichage (vue étudiant par défaut)

- **`[ PASSED ]` / `[ NOT PASSED ]`** pour chaque critère (pas de points : la notation
  est faite par le correcteur).
- **Taille attendue vs trouvée** sur les partitions.
- Quand c'est `NOT PASSED` → la **commande exacte pour corriger** (`→ corriger : …`).
- `[À VÉRIFIER]` pour ce qui dépend du jugement humain (clavier natal, fuseau).
- Section **Bonus détectés** (chiffrement LUKS, ricing, outils pentest…).
- Un **test SSH réel** (si la clé est disponible sur la machine).
- Un **récapitulatif** final : ce qui passe / la liste de ce qui reste à corriger.

> Une copie est aussi écrite dans `flint_result_<os>.txt` (ignoré par git).

### Mode correcteur (réservé à l'évaluateur)

```bash
sudo ./flint_test.sh --score          # affiche les points + le total
sudo ./flint_test.sh --score arch     # forcer l'OS si besoin
```
Affiche les points par critère, le total de l'OS, et — si Arch **et** Fedora ont été
lancés — un **TOTAL COMBINÉ**.

## Lecture des résultats

| Symbole | Signification |
|---------|---------------|
| `[ OK ]` | Critère validé automatiquement (points comptés) |
| `[FAIL]` | Critère non validé (affiche la valeur trouvée pour vous aider à corriger) |
| `[ ?? ]` | **À vérifier par le correcteur** : valeur affichée, jugement humain requis (clavier natal, fuseau horaire…) |

À la fin, un **SCORE AUTOMATIQUE** récapitule les points testables automatiquement.

## Ce que le script NE teste PAS (évaluation manuelle)

- **Mandatory** : présence d'un *snapshot* de la VM à la date du rendu, et connexion SSH
  **depuis l'extérieur** (`ssh -i ~/.ssh/flint -p 4242 pierre@<IP>`).
- **Oral** : 2 questions de cours.
- **Tests pratiques** : 2 manipulations en direct.
- **Bonus** : chiffrement de partition, Parrot/pentest, personnalisation, etc.
- Les lignes `[ ?? ]` (langue natale du clavier, fuseau horaire de l'étudiant).

## Tolérances de taille

Les tailles de partitions sont comparées avec une **marge** (un `15G` réel fait
souvent ~14,6 Gio). Plages utilisées :

| Partition | Cible | Plage acceptée |
|-----------|-------|----------------|
| Arch root | 15 Go | 13–17,5 Gio |
| Arch home | 5 Go  | 4,3–6 Gio |
| Fedora root | 20 Go | 17–23 Gio |
| Fedora home | 10 Go | 8,5–12 Gio |
| boot / EFI | 512 Mo | 400–700 Mio |
| swap | 2 Go | 1,7–2,4 Gio |

## Avertissement

Script fourni « tel quel », sans garantie. Il lit des fichiers système en lecture seule
et ne modifie **rien** sur la machine. Vérifiez toujours avec le barème officiel.
