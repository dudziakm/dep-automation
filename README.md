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

## Skrypty

```bash
# Klasyfikacja repo pod preset. Wypisuje TSV na stdout.
./scripts/classify.sh > repos.tsv

# Zasiew renovate.json do repo docelowych (PR na gałęzi). Domyślnie dry-run.
./scripts/seed.sh repos.tsv            # pokazuje, co by zrobił
APPLY=1 ./scripts/seed.sh repos.tsv    # realnie tworzy PR-y
```

`repos.tsv` w repo jest snapshotem klasyfikacji, nie źródłem prawdy. Przegeneruj
go przed każdą większą zmianą zakresu.

## Instalacja aplikacji Renovate

Zasiew `renovate.json` musi nastąpić **przed** instalacją aplikacji. Renovate
wykrywa istniejący config i pomija PR onboardingowy; bez tego dostaniesz
onboarding z gołym `config:recommended`, czyli bez tej polityki.

1. `APPLY=1 ./scripts/seed.sh repos.tsv` i scal PR-y.
2. Zainstaluj aplikację: https://github.com/apps/renovate
3. Wybierz repozytoria z kolumny `preset` różnej od `skip`.
4. Sprawdź Dependency Dashboard w kilku repo, zanim rozszerzysz zakres.
