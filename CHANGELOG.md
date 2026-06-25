# Changelog

## 0.1.2

- Cache recent unique history commands to avoid scanning and sorting the full history on every key press.
- Scan history from the current history event backwards instead of sorting all history keys.
- Delay loose fuzzy matching until longer queries and only run it when higher-quality matches are not enough.
- Add result limits for path completion in large directories.
- Document performance tuning options.

## 0.1.1

- Make Tab path completion work for the first command-line word after any input.
- Keep native Zsh completion only for an empty command line.

## 0.1.0

- Add realtime history candidate display.
- Add Up and Down history selection.
- Add number-based candidate selection.
- Add current-directory path completion for command arguments.
- Add configurable result count and selected marker.
