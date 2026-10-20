# Moon-Lander docs site

`moonrockz/moon-lander-site` builds the static docs site of this repository. It is a
docs tool and is not published.

| Package | Content | Targets |
| --- | --- | --- |
| `model` | Site configuration, routes and build problems | all four |
| `views` | Rabbita page layout | `native` |
| `generate` | Executable that reads the repository and writes `_site/` | `native` |
| `check` | Executable that checks the links of a built `_site/` | `native` |

The site configuration is `site/site.json` at the repository root. The landing page
is `site/pages/index.html`. Static assets are in `apps/site/assets/`.

Build the site from the repository root:

```shell
mise run build:site
mise run check:site
```

The output is `_site/`. Each route is a directory with `index.html`, and each link
starts with the `base_path` of `site/site.json`. The design is in
`openspec/changes/add-docs-site/design.md`.
