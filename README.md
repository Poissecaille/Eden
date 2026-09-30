# Extinct

![Carte générée](docs/screenshot.png)

Générateur de cartes 2D procédurales en vue de dessus, fait avec **Godot 4.3**.

Deux bruits de Perlin (élévation et humidité) déterminent le biome de chaque case :
eau, sable, plaine, forêt, collines, marais, désert, montagne, neige. Les biomes texturés
sont habillés de variantes d'herbe fondues entre elles et d'objets dispersés (arbres,
buttes, touffes, rochers) qui prennent la couleur du sol sous eux. Les biomes sans
texture sont pour l'instant affichés en couleur unie.

## Lancer

Ouvrir le projet dans Godot 4.3 et lancer la scène principale (`main.tscn`), ou F5 depuis
VS Code avec l'extension *godot-tools*.

| Touche | Action |
|---|---|
| R | nouvelle carte |
| I | mode île |
| ZQSD / flèches | déplacer la caméra |
| Molette | zoomer |
| Clic droit maintenu | faire glisser la vue |

## Organisation

```
main.tscn                  scène principale
world/
  world_generator.gd       génération : bruit, choix des biomes, pose des tuiles et des objets
  biome.gd                 définition d'un biome (seuils, texture, objets)
  prop_scatter.gd          dessin des objets du décor
  camera_controller.gd     caméra
  shaders/                 fondu des variantes d'herbe, teinte des objets selon le sol
  assets/                  atlas utilisés par le jeu (+ sources/ : images d'origine)
```

Les biomes se règlent dans l'inspecteur du nœud `World` (liste `biomes`).
