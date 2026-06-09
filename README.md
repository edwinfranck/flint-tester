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

À la fin : un résumé `X PASSED / Y NOT PASSED` pour l'OS courant.

## Avertissement

Script fourni « tel quel ». Il lit des fichiers système en **lecture seule** et ne
modifie **rien**. Le barème officiel et le correcteur gardent le dernier mot.
