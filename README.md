# dep-automation

Centralne presety Renovate dla repozytoriów `dudziakm`. Każde repo objęte
automatyzacją ma jednolinijkowy `renovate.json`, cała polityka mieszka tutaj.

Repo jest **publiczne** świadomie: Renovate musi umieć pobrać preset przez
`github>dudziakm/dep-automation`, a presety nie zawierają żadnych sekretów.

## Presety

| Plik | Referencja | Dla kogo |
|---|---|---|
| `default.json` | `github>dudziakm/dep-automation` | Baza. Sama nie wystarcza — używaj warstwy poniżej. |
| `js.json` | `github>dudziakm/dep-automation:js` | Repo JS/TS/Node |
| `jvm.json` | `github>dudziakm/dep-automation:jvm` | Repo Maven/Gradle |
| `mixed.json` | `github>dudziakm/dep-automation:mixed` | Repo z manifestami JS **i** JVM |
| `silent.json` | `github>dudziakm/dep-automation:silent` | Repo uśpione: dashboard tak, PR-y nie |

`js.json`, `jvm.json` i `silent.json` same rozszerzają `default.json`, więc config
w repo docelowym to jedna linia:

```json
{ "extends": ["github>dudziakm/dep-automation:js"] }
```

## Faza 2 świadomie nie robi automerge

W tej fazie `automerge` jest wyłączony **wszędzie**. Celem jest najpierw
zobaczyć, ile i jakich PR-ów Renovate generuje, a dopiero potem otwierać bramki.
Automerge włączymy per warstwa, gdy repo będzie miało realną bramkę CI.

Trzy ustawienia decydują o tym, czy automerge byłby fail-closed, i wszystkie trzy
są tu ustawione jawnie w `default.json`:

- `platformAutomerge: false` — **to nadpisanie, nie wartość domyślna.** W źródle
  Renovate ta opcja ma `default: true`. Domyślnie Renovate zleciłby scalanie
  GitHubowi, a bez branch protection (niedostępnego dla repo prywatnych w planie
  Free) GitHub potrafi scalić PR-a, zanim testy wystartują albo już po ich
  porażce. Ustawienie `false` przenosi decyzję do Renovate, który sam sprawdza
  status checków.
- `ignoreTests: false` — domyślne, trzymane jawnie. `true` scalałoby bez testów.
- `internalChecksAsSuccess: false` — domyślne, trzymane jawnie. Zapobiega
  traktowaniu własnych checków Renovate (np. `renovate/stability-days`) jako
  zielonego CI, gdy repo nie ma żadnego prawdziwego workflow.

`minimumReleaseAgeBehaviour`, `internalChecksFilter` i
`dependencyDashboardReportAbandonment` też są ustawione na swoje wartości
domyślne. To celowe: zapisujemy intencję, żeby zmiana domyślnej po stronie
Renovate nie zmieniła nam po cichu polityki.

## Kluczowe decyzje

**Kwarantanna 7 dni (`minimumReleaseAge`).** Najtańsza realna obrona przed
skażoną paczką. Nie chroni istniejącego drzewa — `npm ci` nie robi ponownego
rozwiązywania zależności — tylko nowe rozwiązania, i to jest właściwe zachowanie.
Łatki bezpieczeństwa pomijają kwarantannę przez blok `vulnerabilityAlerts`.

**Bloku `overrides` nie ruszamy** (`js.json`, `matchDepTypes: overrides`). To
polityka bezpieczeństwa pisana ręcznie, nie zależność. Renovate i Dependabot nie
są narzędziami do naprawy podatności przechodnich i nie należy im tego oddawać.

**Nie ruszamy zależności zarządzanych przez BOM** (`jvm.json`). Renovate nie
uruchamia Mavena, więc nie widzi, że Maven i tak zresetuje wersję do tej z BOM-a.
Powstałby PR, który przechodzi build i jednocześnie kłamie o tym, co realnie
zostanie użyte.

**Cypress i Playwright w grupach.** Wtyczki mają wąskie zakresy `peer` na wersję
runnera. Rozjechanie ich to dokładnie ta klasa błędu, którą naprawialiśmy ręcznie
w `playwright-lum-project-cypress`.

**`osvVulnerabilityAlerts` jest oznaczone w Renovate jako eksperymentalne.**
Zostawiam włączone, bo baza OSV jest odpytywana lokalnie (bez limitów zapytań),
ale traktuj to jako sygnał, nie gwarancję, i licz się ze zmianą zachowania.

**`silent.json` nie używa `mode: silent`.** Nazwa presetu jest myląca i to celowy
kompromis — nazwa została, zachowanie się zmieniło. `mode: silent` blokuje nie
tylko PR-y i gałęzie, ale **także utworzenie samego Dependency Dashboardu**, więc
repo w tym trybie jest kompletnie niewidoczne. Sprawdzone uruchomieniem:

```
INFO: Repository is running with mode=silent and will not make Issues or PRs by default
```

i w tym samym przebiegu **brak** linii `Would ensure Dependency Dashboard`, którą
Renovate wypisuje dla repo w trybie zwykłym. Zamiast tego używamy
`dependencyDashboardApproval: true`: dashboard powstaje i wypełnia się listą
aktualizacji, ale żadna gałąź ani PR nie powstaje, dopóki człowiek nie odhaczy
pozycji. Efekt jest ten, o który chodziło — widoczność bez kosztu.

Uwaga na kolejność nadpisań: `mode` z presetu wygrywa z `RENOVATE_MODE` w
zmiennych środowiskowych, więc tego nie da się obejść z linii poleceń.

## Pułapka: walidator nie sprawdza zdalnych presetów

`renovate-config-validator` **nie pobiera** presetów wskazanych przez `github>`.
Config z celowo błędnym `github>dudziakm/dep-automation:nie-ma-takiego`
przechodzi u niego jako poprawny (sprawdzone). Znaczy to, że zmiana nazwy pliku
presetu nie zostałaby wyłapana przez walidację, a wysypałaby się dopiero u bota,
w każdym repo naraz.

Dlatego workflow ma osobny krok sprawdzający odniesienia między presetami po
plikach. Pełne, prawdziwe rozwiązanie presetu daje tylko uruchomienie Renovate:

```bash
mkdir -p /tmp/rnvdry && cd /tmp/rnvdry
cat > config.js <<'EOF'
module.exports = {
  platform: 'github',
  repositories: ['dudziakm/testPwSetup'],
  extends: ['github>dudziakm/dep-automation:js'],
  requireConfig: 'optional',
  dryRun: 'extract',
};
EOF
RENOVATE_CONFIG_FILE=/tmp/rnvdry/config.js \
RENOVATE_TOKEN="$(gh auth token)" GITHUB_COM_TOKEN="$(gh auth token)" \
  npx --package renovate@latest renovate
```

Błędna nazwa daje wtedy `config-presets-invalid` i `Cannot find preset's
package`.

## Skrypty

```bash
# Klasyfikacja repo pod preset. Wypisuje TSV na stdout.
./scripts/classify.sh > repos.tsv

# Zasiew renovate.json do repo docelowych (PR na gałęzi). Domyślnie dry-run.
./scripts/seed.sh repos.tsv            # pokazuje, co by zrobił
APPLY=1 ./scripts/seed.sh repos.tsv    # realnie tworzy PR-y

# Scalenie zasianych PR-ów z gałęzi chore/renovate-config.
./scripts/merge-seeded.sh repos.tsv

# Rozpoznanie kształtu repo JS (manager, build, typecheck, tsconfig, liczba paczek).
./scripts/shapes.sh repos.tsv

# Zasiew bramki verify do aktywnych repo JS. Domyślnie dry-run.
./scripts/seed-verify.sh repos.tsv            # pokazuje, co by zrobił
APPLY=1 ./scripts/seed-verify.sh repos.tsv    # realnie tworzy PR-y
ONLY=repoA,repoB APPLY=1 ./scripts/seed-verify.sh repos.tsv
```

`repos.tsv` w repo jest snapshotem klasyfikacji, nie źródłem prawdy. Przegeneruj
go przed każdą większą zmianą zakresu.

Każdy skrypt, który cokolwiek zapisuje, zaczyna od porównania `gh api user` z
`OWNER` i przerywa przy niezgodności. To nie jest ostrożność na wyrost: na
maszynie z kilkoma kontami `gh` push przechodzi (git ma własne poświadczenia), a
dopiero `gh pr create` kończy się `must be a collaborator` — i zostają wypchnięte
gałęzie bez PR-ów.

## Bramka verify i jej realny zasięg

`templates/verify-js.yml` to warunek wstępny automerge: instalacja z lockfile'a,
`tsc --noEmit` gdy repo ma TypeScript w zależnościach, `build` gdy istnieje taki
skrypt. Świadomie **nie uruchamia E2E** — zestawy Playwrighta i Cypressa w tych
repo celują w zewnętrzne serwisy, z których część zniknęła, a część blokuje ruch
z adresów centrów danych. Jako bramka dawałyby szum zamiast dowodu.

Bramka jest potwierdzona testem kontrolnym, nie tylko rozumowaniem. W
`testPwSetup` podmieniono `@playwright/test` na nieistniejącą wersję `1.99.99`;
workflow zapalił się na czerwono na kroku `Instalacja` z `npm error code ETARGET`.
Po odczytaniu wyniku gałąź i PR zostały usunięte.

Trzeba jednak znać granice tego sygnału:

- **Repo bez `build` i bez TypeScriptu w zależnościach dostają bramkę
  install-only.** Dotyczy to większości repo testowych. `npm ci` nadal wyłapuje
  nieistniejącą wersję, rozjechany lockfile, konflikt `peer` i sprzeczny
  `overrides` — ale nie wyłapie regresji zachowania.
- **`tsc --noEmit` przy `skipLibCheck: true` jest słabsze, niż się wydaje.**
  Sprawdzone na `web-ideas/projects/program-tv`: downgrade `next` z `^16.3.0` na
  `14` oraz `lucide-react` z `^0.525.0` na `0.100.0` przeszedł i typecheck, i
  build na zielono.
- Dlatego workflow kończy się krokiem, który wypisuje do podsumowania zadania,
  które etapy faktycznie się wykonały. Zielona bramka install-only ma o tym
  mówić wprost, zamiast udawać pełne pokrycie.

Nie rozsiewaj bramki szerzej, niż potrzeba: repozytoria są prywatne, więc minuty
Actions realnie się zużywają. Z tego samego powodu workflow nie ma harmonogramu —
uruchamia się na PR-ach, na `push` do gałęzi domyślnej i ręcznie.

## Instalacja aplikacji Renovate

Zasiew `renovate.json` musi nastąpić **przed** instalacją aplikacji. Renovate
wykrywa istniejący config i pomija PR onboardingowy; bez tego dostaniesz
onboarding z gołym `config:recommended`, czyli bez tej polityki.

1. `APPLY=1 ./scripts/seed.sh repos.tsv` i scal PR-y.
2. Zainstaluj aplikację: https://github.com/apps/renovate
3. Wybierz repozytoria z kolumny `preset` różnej od `skip`.
4. Sprawdź Dependency Dashboard w kilku repo, zanim rozszerzysz zakres.

**Sam config niczego nie uruchamia.** Zasiew `renovate.json` do 54 repozytoriów
nie powoduje żadnego działania bota, dopóki aplikacja nie jest zainstalowana —
nie powstaje ani jeden PR, ani jeden Dependency Dashboard, i nie ma też żadnego
komunikatu o błędzie. Cisza wygląda identycznie jak zepsuty config, więc nie
diagnozuj jej po objawach: sprawdź listę zainstalowanych aplikacji.

Sprawdzenie, czy bot kiedykolwiek cokolwiek zrobił (`0` = nigdy nie przebiegł):

```bash
gh api -X GET search/issues -f q='user:dudziakm author:app/renovate' --jq .total_count
```

Rozdzielenie „config jest zepsuty" od „bot nie działa" — dry-run lokalnie, bez
aplikacji i bez zmian w repo:

```bash
RENOVATE_TOKEN="$(gh auth token -u dudziakm)" \
GITHUB_COM_TOKEN="$(gh auth token -u dudziakm)" \
  npx --yes renovate --dry-run=full --platform=github dudziakm/testPwSetup
```

Zdrowy config kończy się `"status": "activated"`, `"onboarded": true` oraz
liniami `DRY-RUN: Would commit files to branch ...` i `Would ensure Dependency
Dashboard`. Jeśli to widzisz, a na GitHubie nadal cisza, problem jest wyłącznie
w zasięgu instalacji aplikacji.

Aplikacja Renovate jest darmowa również dla repozytoriów prywatnych (plan Mend
Renovate Community Cloud), więc prywatność tych repo nie jest przeszkodą. Limity
planu darmowego to jedno zadanie równolegle na konto i przebieg co ~4 godziny —
przy 54 repozytoriach pierwszy pełny obieg trwa, więc nie panikuj po godzinie.

## Dokumentacja i warstwa AI

- [`docs/PLAN-AUTOMATYZACJI.md`](docs/PLAN-AUTOMATYZACJI.md) — pełny plan
  wykonawczy: pomiary, korekty wcześniejszych wniosków, kolejność wdrożenia.
- [`ai/`](ai/README.md) — warstwa providerów AI dla agenta z Fazy 7, który
  próbuje naprawić build padnięty po podbiciu zależności. **DeepSeek Flash
  domyślnie**, DeepSeek Pro na eskalację, OpenRouter jako zapas na awarię
  dostawcy, Gemini opisane ale wyłączone (brak klucza). Przełączenie providera to
  zmiana trzech wartości w `ai/providers.json`, bo wszyscy mówią protokołem
  zgodnym z OpenAI. Tam też opis, gdzie trzymać klucze: na koncie osobistym nie
  ma sekretów Actions na poziomie użytkownika, więc leżą w jednym repo
  sterującym.

Agent AI **nigdy nie jest bramką**: może wyłącznie zaproponować zmianę, a o tym,
czy cokolwiek wjedzie na `main`, decydują deterministyczne checki CI i ocena
statusu przez Renovate.
