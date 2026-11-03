# Shipped Recipes

Each `.json` file in this directory is a game recipe loaded by
`RecipeStore` at runtime. See `docs/RECIPE_AUTHORING.md` for the contribution
workflow and `docs/recipe.v1.schema.json` for the machine-readable schema.

## Layout

```
Recipes/
  steam/       # Steam titles, filename = AppID
  gog/         # GOG titles, filename = GOG product id
  generic/     # Installer-based or out-of-platform titles
```

## Contributing a recipe

1. Confirm the game boots and is playable on your Apple Silicon Mac.
2. Copy the closest matching existing recipe in the same platform folder.
3. Update `id`, `title`, `dx_version`, `renderer`, `winetricks`, `env`,
   `compatibility`, and `notes`.
4. Open a PR. CI runs schema validation and rejects malformed recipes.
