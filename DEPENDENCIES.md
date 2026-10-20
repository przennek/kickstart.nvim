# Zależności

Konfiguracja działa na Arch Linux i macOS. Wymaga **Neovim ≥ 0.12.5**. Pluginy, serwery
językowe, debuggery, lintery i parsery treesittera instalują się same przy pierwszym starcie
(lazy.nvim + Mason) — potrzebne są tylko narzędzia systemowe poniżej.

Bez któregoś z języków (Go, Node/npm, Python, Java) konfiguracja i tak startuje: narzędzia,
które go wymagają, są pomijane i raz pokazuje się komunikat, czego brakuje.

## Arch Linux

```sh
sudo pacman -S --needed - < deps/arch-packages.txt
yay -S --needed - < deps/aur-packages.txt      # mongosh (MongoDB)
```

## macOS

```sh
xcode-select --install                          # kompilator C i make
brew bundle --file=deps/Brewfile
brew link --force libpq                         # psql na PATH
```

`clangd` z `brew llvm` nie trafia na PATH — wtedy używany jest clangd z Masona (sam się instaluje).

## Java (oba systemy)

Java, Maven i Gradle przez [SDKMAN](https://sdkman.io) — konfiguracja bierze JDK z
`~/.sdkman/candidates/java/current`, także gdy Neovim startuje bez powłoki:

```sh
curl -s "https://get.sdkman.io" | bash
sdk install java          # jdtls wymaga JDK 21+
sdk install maven
sdk install gradle
```

## Terminal

Skróty w stylu IntelliJ, których terminal sam nie wyśle (`Ctrl+Tab`, `Ctrl+Shift+F/R/B/P/N/M`,
`Ctrl+Enter`, `Ctrl+Alt+M`, `Alt+Shift+F12`), tłumaczy terminal:

- **Linux**: Alacritty — `extras/alacritty/linux.toml` → `~/.config/alacritty/alacritty.toml`
  (zakłada też tmux jako powłokę startową).
- **macOS**: iTerm2 — profil `extras/iterm2/nvim-idea.json`. Zamknij iTerm2 (`Cmd+Q`) i z
  Terminal.app uruchom:

  ```sh
  extras/iterm2/install.sh
  ```

  Skrypt podpina profil „Neovim (IntelliJ keys)” i ustawia go jako domyślny oraz zwalnia
  `Cmd+1…9`: iTerm2 domyślnie przełącza nimi karty *zanim* zadziała mapowanie z profilu, więc
  `Cmd+1` nic nie robiło, a drzewo otwierało tylko `Option+1`. Ręcznie to samo: *Settings → Keys
  → Navigation Shortcuts → Shortcut to choose a tab: No shortcut* oraz *Settings → Profiles →
  „Neovim (IntelliJ keys)” → Other Actions → Set as Default*. Karty iTerm2 przełączysz z menu
  *Window* (profil i tak startuje tmux, więc zwykle wystarcza jedna karta).
  Profil dziedziczy po „Default”, uruchamia tmux i wysyła `Cmd+<klawisz>` jako `Alt+<klawisz>` —
  wciskasz to samo co w IntelliJ na Macu. Option działa jako Esc+, więc `Option+<klawisz>` daje
  to samo co `Cmd+<klawisz>` (nie przeszkadza, ale nie trzeba go używać).
  `Cmd+C` / `Cmd+V` / `Cmd+Q` / `Cmd+Tab` zostają skrótami macOS.

Czcionka: JetBrains Mono Nerd Font (ikony w drzewie, na pasku statusu, w debuggerze).

## Pierwszy start

1. `nvim` — lazy.nvim pobiera pluginy, Mason instaluje narzędzia (`:Mason` pokazuje postęp).
2. Parsery treesittera budują się, gdy Mason zainstaluje `tree-sitter-cli`.
3. Przy kolejnym starcie wszystko jest gotowe.

## Opcjonalne

| Co | Po co |
|---|---|
| `pmd` na PATH | PMD w Javie (nie ma go w Masonie) |
| `checkstyle.xml` w projekcie | Checkstyle w Javie |
| `.venv` w projekcie | interpreter Pythona dla basedpyright i testów |
| `compile_commands.json` w projekcie C | clangd (np. `bear -- make`, CMake `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) |
| konto AWS z SSO w `~/.aws/config` | przełącznik profili `␣A` |
