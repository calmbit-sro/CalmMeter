# ClaudeUsage

Malá macOS menubar appka, která nahoře v liště ukazuje aktuální **Claude usage** —
totéž, co příkaz `/usage` v Claude Code: vytížení **5hodinového** a **týdenního**
limitu, časy resetů, volitelně rozpad po modelech a spend.

## Jak to funguje

Čte OAuth token, který si Claude Code ukládá do macOS Keychainu (služba
`Claude Code-credentials`), a volá `GET https://api.anthropic.com/api/oauth/usage`.
Token si sama neobnovuje — spoléhá, že ho Claude Code drží čerstvý; při vypršení
zobrazí výzvu spustit `claude`.

Žádná data nikam neposílá kromě dotazu na Anthropic API o tvé vlastní spotřebě.

## Build & spuštění

```bash
swift test              # unit testy (modely, parsování, countdown)
./scripts/build-app.sh  # vytvoří ./ClaudeUsage.app
open ./ClaudeUsage.app  # spustí

# volitelně instalace do /Applications:
./scripts/build-app.sh --install
```

Při **prvním spuštění** macOS zobrazí dialog Keychainu s žádostí o přístup k
`Claude Code-credentials` → dej **Always Allow**. (Appka je jiný podpis než
Claude Code, proto se ptá jednou.)

## Předvolby

Klikni na položku v liště → **Předvolby…**. Nastavitelné:

- **Formát v liště:** tečka + 5h % (výchozí) · jen 5h % · `5h % · týden %` · jen tečka
- **Interval obnovování:** 30 s · 60 s (výchozí) · 5 min
- **Spouštět při přihlášení** (výchozí zapnuto)
- **Rozpad po modelech** v menu (Opus/Sonnet…)
- **Barevné prahy** (zelená / oranžová / červená)

## Struktura

- `Sources/ClaudeUsageCore/` — modely, API klient, Keychain, polling store (testovatelné)
- `Sources/ClaudeUsage/` — SwiftUI menubar app (`MenuBarExtra`)
- `Tests/ClaudeUsageCoreTests/` — unit testy + fixture odpovědi
- `scripts/build-app.sh` — sestavení `.app` bundlu

## Poznámky

- macOS 13+ (`MenuBarExtra`).
- Appka je nepodepsaná (ad-hoc) — pro osobní použití; při prvním otevření může
  Gatekeeper chtít potvrzení „Otevřít i tak".
