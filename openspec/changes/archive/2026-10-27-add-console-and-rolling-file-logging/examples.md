# Proposed logging output

These are illustrative outputs for this proposal, not output from an implemented
sink. Times, categories, messages, and error text are sample application data.
The examples use the proposed fixed layouts and existing level codes. Exact
Literate colors will be checked in real terminals during implementation.

## Console

The default console writes to stderr. This is its plain-text appearance, including
what a redirected stream or a terminal with colors disabled would receive.

```text
[14:23:07.012Z TRC] workspace.discovery: Inspecting /work/acme/src
[14:23:07.018Z DBG] config.loader: Selected environment Development
[14:23:07.024Z INF] workspace.loader: Loaded 3 files from src
[14:23:07.035Z WRN] config.loader: Configuration file optional.toml was not found
[14:23:07.041Z ERR] build.compiler: Compilation failed for app.mbt
    CompilerError: Unknown identifier calculate_total
      at app.mbt:42
[14:23:07.049Z CRT] app: Startup failed; shutting down
```

Without a category, omit the category and its separator:

```text
[14:23:07.024Z INF] Loaded 3 files from src
```

In a Literate terminal, the text stays the same. The formatter styles the
timestamp and category as muted metadata, gives severity its emphasis, and makes
bound values stand out from the surrounding literal text. For example:

| Part of `Loaded 3 files from src` | Role | Suggested appearance |
| --- | --- | --- |
| `Loaded ` and ` files from ` | Literal message text | Muted text |
| `3` | Numeric property `Count` | Bright number color |
| `src` | String property `Path` | Distinct string color |

The colors use the bound JSON types, not guesses about words in the rendered
message. String values retain the existing unquoted rendering. No ANSI escape
codes appear in plain output or files.

## Readable rolling files

For the same events, `acme-20261027.log` would contain full UTC dates:

```text
2026-10-27T14:23:07.024Z [INF] workspace.loader: Loaded 3 files from src
2026-10-27T14:23:07.035Z [WRN] config.loader: Configuration file optional.toml was not found
2026-10-27T14:23:07.041Z [ERR] build.compiler: Compilation failed for app.mbt
    CompilerError: Unknown identifier calculate_total
      at app.mbt:42
```

Message continuation lines also receive an indent:

```text
2026-10-27T14:23:08.100Z [INF] build.summary: Build summary:
    Compiled 12 modules
    Completed in 840 ms
```

Error text appears only when the caller supplies an error. The sink does not
invent a stack trace; additional error lines depend on the captured error text.

With daily and size rolling, the directory could contain:

```text
acme-20261027.log
acme-20261027_001.log
acme-20261027_002.log
acme-20261028.log
```

The numeric suffix advances when a day's file reaches the size rule. The next
UTC day starts a new dated file. The date is part of the filename, not an extra
line inside the file.

## JSON Lines

The same information event in `acme-20261027.jsonl` is one physical line:

```jsonl
{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.024Z","level":"Information","category":"workspace.loader","messageTemplate":"Loaded {Count} files from {Path}","message":"Loaded 3 files from src","properties":[{"name":"Count","value":3},{"name":"Path","value":"src"}],"error":null}
```

An error event also occupies one physical line. Newlines inside error text are
JSON escapes, so a reader can consume one record per line:

```jsonl
{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.041Z","level":"Error","category":"build.compiler","messageTemplate":"Compilation failed for {File}","message":"Compilation failed for app.mbt","properties":[{"name":"File","value":"app.mbt"}],"error":"CompilerError: Unknown identifier calculate_total\n  at app.mbt:42"}
```

Both formats can be enabled together. Their file sets use `.log` and `.jsonl`
respectively, while the event timestamp and structured values come from the same
captured record. JSON Lines keeps numbers as numbers, nullable fields as `null`,
and the original message template alongside the rendered message.
