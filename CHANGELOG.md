# Changelog

## 0.1.5

- Add extra spacing before the live history list in narrow or wrapped terminal displays.

## 0.1.4

- Make path completion case-insensitive while preserving the real on-disk path casing.

## 0.1.3

- Support tilde path completion, including hidden files such as `~/.zshrc`.
- Add Right-arrow acceptance for the highlighted history candidate.
- Add Esc to hide the visible history candidate list.
- Add a truncation hint when path completion has more matches than the configured limit.
- Add configuration switches for normal number and Alt+number selection bindings.

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
