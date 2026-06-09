# Flint Tester (G-NSA-100) — évaluation PASSED / NOT PASSED

> ⚠️ **Tester NON officiel**, écrit pour remplacer le dépôt `tests-G-NSA-100-gamut`
> qui ne fonctionne pas. Il évalue chaque critère du barème en **PASSED / NOT PASSED**.

## ⚠ Projet DUAL BOOT : à lancer sur LES DEUX OS

Le barème a une partie **Arch** et une partie **Fedora**, testées chacune **depuis
l'OS concerné**. Le script détecte automatiquement où il tourne :

- booté sur **Arch** → il évalue la partie **Arch**
- rebooté sur **Fedora** → il évalue la partie **Fedora**

👉 Lance-le **sur Arch, puis reboote et relance-le sur Fedora**.

## Utilisation

```bash
git clone https://github.com/edwinfranck/flint-tester.git
cd flint-tester
chmod +x flint_test.sh
sudo ./flint_test.sh
```

> Le script se relance tout seul avec `sudo` (lecture de `/etc/shadow`, `sshd_config`…).
> Si l'OS n'est pas détecté : `sudo ./flint_test.sh arch` ou `sudo ./flint_test.sh fedora`.

## Affichage

- **`[  PASSED  ]`** : critère validé.
- **`[NOT PASSED]`** : critère non validé.
- **`[À VÉRIFIER]`** : impossible à juger automatiquement (clavier natal, fuseau
  horaire) → la valeur est affichée, le correcteur tranche.

Pour les **partitions**, en plus du verdict, le script affiche le **nombre de
partitions** trouvées, le **schéma réel du disque** (`lsblk`) et une **comparaison
attendu / trouvé** taille par taille, avec la **plage tolérée**.

### Tolérance sur les tailles

Une marge volontaire est appliquée : un `15G` créé par l'étudiant fait en réalité
15 Gio (≈ 16,1 Go), et le système de fichiers consomme un peu d'espace. Sans marge,
un bon partitionnement échouerait. Réglable en haut du script :

```bash
TOL_PCT=12         # marge en ± % de la taille cible
TOL_MIN_MIB=120    # marge minimale (Mio) pour les petites partitions (boot/EFI)
```

Exemple affiché : `cible 15.0 Gio (toléré 13.2 Gio–16.8 Gio) | trouvé 14.6 Gio → PASSED`.
Mets `TOL_PCT` plus bas (ex. 8) pour être plus strict, plus haut pour être plus souple.

À la fin : un résumé `X PASSED / Y NOT PASSED` pour l'OS courant.

## Enregistrer la sortie dans un fichier .txt

Les couleurs sont automatiquement retirées quand la sortie va dans un fichier :

```bash
sudo ./flint_test.sh arch | tee resultat_arch.txt   # à l'écran + dans le fichier
sudo ./flint_test.sh arch > resultat_arch.txt 2>&1  # uniquement dans le fichier
```

## Avertissement

Script fourni « tel quel ». Il lit des fichiers système en **lecture seule** et ne
modifie **rien**. Le barème officiel et le correcteur gardent le dernier mot.
