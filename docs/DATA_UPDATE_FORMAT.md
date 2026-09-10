# v0.7 Bastion Data Update Format

Root:
```json
{
  "format": "eq-research-update-pack",
  "version": 1,
  "server": "Bastion",
  "spellCatalog": [],
  "researchRecipes": []
}
```

## spellCatalog row
Required:
- `name`

Optional:
- `classes`: array such as `["CLR"]`
- `acquisition`: `["Research","Drop"]`
- `researchStatus`: `MAPPED`, `PARTIAL`, `CONFIRMED_UNRESOLVED`, `NONE`, `UNKNOWN`
- `bastionUrl`
- `notes`
- `era`
- `levelByClass`: object such as `{"CLR":60}`
- `researchEvidence`: array of source objects

## researchRecipes row
Required:
- `spell`
- `components`

Optional:
- `class`
- `level`
- `trivial`
- `containers`
- `sourceUrl`
- `era`
- `notes`
- `complete`

Components should use exact item IDs whenever Bastion exposes separate IDs for same-name pieces.
