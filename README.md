# Marée Montante — prototype

Roguelite mobile solo (Godot 4.3, GDScript) : une colonie protège son île d'une marée qui monte à chaque tour.
Prototype jouable du MVP, rendu avec des cubes et primitives (pas encore de modèles Blender).

## Lancer

1. Ouvrir le dossier dans **Godot 4.3+** (Projet > Importer > `project.godot`).
2. F5. La fenêtre est en portrait (720×1280, réduite à 405×720 sur ordinateur). La souris émule le doigt.

Rendu : `GL Compatibility`, le plus sûr pour Android/iOS d'entrée de gamme.

## Ce qui est en place (périmètre MVP du GDD)

| GDD | Prototype |
| --- | --- |
| Grille générée par bruit | Grille **carrée** 12×12, `FastNoiseLite` (Perlin) + atténuation radiale, altitude 0–30, seed par partie |
| Montée et prévision | La mer monte d'un niveau par tour. L'eau entre par les bords et envahit les cases plus basses que la mer, **sauf à travers les digues** (on peut garder des polders sous le niveau de la mer). Cases englouties au prochain tour en bleu pulsé qui vibre |
| 3 actions par tour | Récolter (forêt = bois, colline = pierre, rivage = pêche, ailleurs = cueillette), Déplacer un groupe, Bâtir |
| 5 bâtiments de départ | Digue en bois (tient 3 marées), digue en pierre (cède si une tempête la submerge), champ (+2 nourriture/tour), pont (rend une case d'eau praticable), radeau (déplacement vers un autre îlot, consommé) |
| 3 événements | Tempête (+2 niveaux), marée basse (aucune montée), naufragés (à aller chercher sur le rivage avant qu'ils ne coulent) |
| Règles | 1 nourriture par habitant et par tour, sinon des habitants partent. Habitants noyés si leur case est engloutie. Défaite quand il n'y a plus personne |
| Défaite, score, Souvenirs | Score = tours × 10 + population max × 5 + naufragés sauvés × 5. Souvenirs = tours + naufragés sauvés (×1,5 au défi du jour). Record personnel affiché |
| 10 déblocages | Colon de plus, Réserves, Scierie, Tailleurs de pierre, Ponts légers, Digues renforcées, Phare, Pilotis, Moulin à marée, Longue-vue (prévision à 2 tours) |
| Défi quotidien | Seed = date du jour, classement local (top 5 du jour) |
| Sauvegarde locale | `ConfigFile` dans `user://maree_montante.cfg` |
| Palette qui suit la tension | Ciel, lumière et eau virent du chaud au froid à mesure que l'île disparaît |

## Organisation

- `scripts/island.gd` : toute la logique de jeu, sans rendu (testable en headless).
- `scripts/board_view.gd` : rendu 3D (cubes, décor, eau, surbrillances, sélection au doigt).
- `scripts/game.gd` : une partie (caméra orthographique inclinée, interface en bas d'écran).
- `scripts/main.gd` : menu, déblocages, écran de défaite.
- `scripts/save_data.gd` : autoload `Save`, méta-progression et classement local.
- `shaders/water.gdshader` : eau low-poly facettée animée.

## Tests

```sh
# 400 parties simulées par un joueur automatique naïf : vérifie la logique et donne la durée des parties
godot --headless --script res://tests/sim_test.gd

# Captures d'écran de contrôle (nécessite un affichage)
godot res://scenes/main.tscn -- --capture /tmp/captures
```

Avec le joueur automatique naïf, une partie dure 19 tours en médiane (max 28).

## Choix faits pour le prototype

- **Grille carrée** plutôt qu'hexagonale : plus simple à coder et à lire au doigt. Passer à l'hexagonal ne touche que `neighbors()`, `tile_pos()` et la sélection.
- Cubes posés en `MeshInstance3D` plutôt que `GridMap` : pas de `MeshLibrary` à maintenir tant qu'il n'y a pas de modèles. `GridMap` reviendra avec les modèles Blender.
- Un déplacement emmène tout le groupe d'une case.
- Les valeurs (coûts, probabilités d'événements, nourriture de départ) sont des premiers réglages à ajuster en test.
