# Warstwa providerów AI

Ta warstwa istnieje dla jednego zastosowania: **agenta, który próbuje naprawić
build padnięty po podbiciu zależności** (Faza 7 planu — patrz
[`docs/PLAN-AUTOMATYZACJI.md`](../docs/PLAN-AUTOMATYZACJI.md)).

## Zasada nadrzędna: agent nigdy nie jest bramką

Agent AI może **wyłącznie** zaproponować zmianę — czyli wystawić PR-a albo oddać
patch jako artefakt. Nie ma prawa:

- ocenić, czy PR przeszedł weryfikację,
- scalić czegokolwiek,
- ustawić statusu checka, na którym opiera się decyzja o merge.

Bramką są i pozostają deterministyczne checki CI plus ocena statusu przez
Renovate. Powód jest konkretny: głównym ryzykiem nie jest złośliwy
współpracownik, a **zatruty changelog paczki, który agent przeczyta jako
instrukcję**. Model, który potrafi zostać przekonany treścią wejścia, nie może
decydować o tym, co wjeżdża na `main`.

Dlatego w tej warstwie nie ma i nie będzie żadnej ścieżki do `pull_request:
write` ani do merge'a.

## Dlaczego przełączenie providera to zmiana trzech wartości

Wszyscy providerzy w [`providers.json`](providers.json) mówią tym samym
protokołem: `POST {base_url}/chat/completions` w formacie OpenAI, z kluczem w
nagłówku `Authorization: Bearer`. To znaczy, że przełączenie providera nie
dotyka kodu — zmienia się:

1. **base URL** (`base_url`),
2. **nazwa sekretu** (`secret`) — czyli skąd wziąć klucz,
3. **nazwa modelu** (`model`).

To sprawdzone empirycznie, nie założone: ten sam `ai-call.sh` bez żadnej zmiany
dostał poprawną odpowiedź z DeepSeeka (`api.deepseek.com`) i z OpenRoutera
(`openrouter.ai`), a przez OpenRouter także z modeli Gemini. Szczegóły w sekcji
„Co zostało potwierdzone empirycznie".

### Jak przełączyć — trzy sposoby, od najmniej do najbardziej trwałego

```bash
# 1. Jednorazowo, na jedno wywołanie:
echo "$PROMPT" | ai/scripts/ai-call.sh -p deepseek

# 2. Na całą sesję albo joba CI, bez dotykania repo:
AI_PROVIDERS_CONFIG=/sciezka/do/wlasnego-providers.json ai/scripts/ai-call.sh ...

# 3. Na stałe: zmień .lancuch.domyslny w ai/providers.json i scal PR-a.
```

## Łańcuch: Flash → Pro → DeepSeek

| Rola | Provider | Model | Kiedy wchodzi |
|---|---|---|---|
| domyślny | `gemini-flash` | `gemini-3.6-flash` | każde pierwsze podejście |
| eskalacja | `gemini-pro` | `gemini-3.1-pro-preview` | trudniejszy przypadek, albo gdy Flash zawiódł |
| zapas | `deepseek` | `deepseek-v4-flash` | Gemini niedostępny: 429, 5xx, wyczerpany limit |
| przewidziany, **wyłączony** | `openrouter` | `google/gemini-3.7-flash` | dopiero gdy będzie potrzebny do czegoś innego |

`ai-call.sh` przechodzi ten łańcuch automatycznie. Provider jest pomijany, gdy
brakuje jego sekretu albo gdy odpowiedź nie nadeszła. Eskalację można też wywołać
od razu:

```bash
# Od razu Pro, bo wiem, że przypadek jest trudny:
echo "$PROMPT" | ai/scripts/ai-call.sh --escalate

# Tylko domyślny, bez eskalacji i bez zapasu (np. gdy pilnuję kosztu):
echo "$PROMPT" | ai/scripts/ai-call.sh --no-escalate
```

### Kiedy eskalować na Pro

Eskalacja jest **droga**: Pro to `$2,00 / $12,00` za milion tokenów wejścia i
wyjścia, wobec `$1,50 / $7,50` dla Flasha, a przy prompcie powyżej 200 tys.
tokenów odpowiednio `$4,00 / $18,00`. Do tego Pro **nie ma darmowego tieru** —
Google zdjęło modele Pro z Free 01.04.2026. Dlatego:

- **Flash jest domyślny zawsze.** Typowa naprawa po podbiciu zależności to
  odczytanie loga `npm ci` albo `mvn verify` i jedna zmiana w manifeście. To nie
  wymaga najmocniejszego modelu.
- **Pro tylko wtedy, gdy Flash nie dał rady**: zwrócił błąd, zwrócił pustą
  odpowiedź, albo jego propozycja nie przeszła bramki CI (i to CI stwierdziło, że
  nie przeszła — nie model).
- **Nie eskalujemy w pętli.** Jeden przebieg Flash, jeden Pro. Jeśli oba nie
  poradziły, sprawa idzie do człowieka. Pętla „próbuj dalej" to najprostszy
  sposób na niekontrolowany rachunek.

### Rola DeepSeeka

DeepSeek to **zapas na wypadek awarii, nie druga opinia**. Jest tu, bo:

- to **niezależny dostawca i niezależny klucz** — awaria czy wyczerpany limit po
  stronie Google go nie dotyka,
- jego API jest **zgodne z OpenAI** (potwierdzone empirycznie), więc nie wymaga
  ani jednej linii kodu więcej,
- jest **najtańszy z trójki**: `$0,22 / $0,66` za milion tokenów poza godzinami
  szczytu, `$0,44 / $1,32` w szczycie.

Nie jest domyślny świadomie: wybrałeś Gemini jako główny punkt dostępu, a
mieszanie providerów bez powodu tylko rozmywa to, gdzie w razie problemu szukać
przyczyny.

### Rola OpenRoutera

`openrouter` ma w konfiguracji status `wyłączony` i **nie występuje w
łańcuchu**. Jest opisany, żeby włączenie go było zmianą jednego pola, a nie nową
robotą. Włączamy go dopiero wtedy, gdy pojawi się potrzeba, której nie zaspokoi
ani Google, ani DeepSeek — na przykład dostęp do modelu innego dostawcy bez
zakładania u niego konta.

Świadoma wada, którą warto znać przed włączeniem: OpenRouter dodaje **jeszcze
jednego pośrednika** w ścieżce, przez którą przechodzi treść cudzych changelogów
czytanych przez agenta. Przy agencie, którego głównym ryzykiem jest prompt
injection, każdy dodatkowy hop to dodatkowa powierzchnia.

`ai-call.sh` pozwala go użyć jawnie, ale wtedy głośno o tym mówi:

```
$ ai/scripts/ai-call.sh -p openrouter
UWAGA: provider 'openrouter' ma w konfiguracji status 'wyłączony'. Uzywam go, bo zazadano go jawnie przez --provider.
```

## Sekrety

W konfiguracji trzymamy **wyłącznie nazwy** zmiennych. Wartości nigdy nie trafiają
do repo.

| Sekret | Dla kogo | Skąd wziąć | Wymagany |
|---|---|---|---|
| `GEMINI_API_KEY` | `gemini-flash`, `gemini-pro` | [Google AI Studio](https://aistudio.google.com/apikey) | tak — to główna ścieżka |
| `DEEPSEEK_API_KEY` | `deepseek` | [platform.deepseek.com](https://platform.deepseek.com/) | zalecany — zapas |
| `OPENROUTER_API_KEY` | `openrouter` | [openrouter.ai/keys](https://openrouter.ai/keys) | nie — dopiero gdy włączysz |

W GitHubie ustawiasz je jako **secrets** (nie variables), najlepiej na poziomie
organizacji lub jako sekret środowiska, żeby jeden wpis obsłużył wszystkie repo:

```bash
gh secret set GEMINI_API_KEY --repo dudziakm/dep-automation
gh secret set DEEPSEEK_API_KEY --repo dudziakm/dep-automation
```

Klucze Gemini generowane w AI Studio są domyślnie ograniczone do Gemini API.
Jeśli używasz klucza z Google Cloud Console, ogranicz go ręcznie do
`generativelanguage.googleapis.com` — od 19.06.2026 Gemini API odrzuca
nieograniczone klucze. *(Źródło: komunikat na forum Google AI Developers,
powtarzany w wielu wątkach; nie znalazłem go na stronie dokumentacji, więc
traktuj jako niepotwierdzone oficjalnym dokumentem.)*

### Jak skrypt chroni klucz

- Klucz jest czytany **tylko** ze zmiennej środowiskowej o nazwie z
  konfiguracji, przez `printenv`.
- Klucz **nie trafia do argumentów procesu**: adres i nagłówek autoryzacji idą do
  `curl` przez plik konfiguracyjny na stdin (`curl --config -`). Sprawdzone: w
  trakcie wywołania klucza nie widać w `ps -Ao args`.
- Każdy komunikat błędu przechodzi przez funkcję `scrub`, która wyciera z niego
  wartość klucza, zanim tekst pójdzie na stderr.
- Klucz o nietypowych znakach (cudzysłów, backslash, nowa linia) jest
  **odrzucany**, a nie cytowany na siłę — lepiej jasny błąd niż zepsuty nagłówek.

## Użycie `ai-call.sh`

```bash
ai/scripts/ai-call.sh --help      # pełna lista opcji
ai/scripts/ai-call.sh --list      # co jest w konfiguracji
ai/scripts/ai-call.sh --check     # które sekrety są ustawione (bez wartości)
echo "prompt" | ai/scripts/ai-call.sh --dry-run   # co by zrobił, bez sieci

# realne wywołanie: prompt z pliku albo ze stdin, odpowiedź na stdout
ai/scripts/ai-call.sh prompt.txt > odpowiedz.md
```

Diagnostyka (który provider, jaki model, ile tokenów) idzie na **stderr**, sama
odpowiedź modelu na **stdout** — więc `> plik` daje czystą odpowiedź.

### Kody wyjścia

| Kod | Znaczenie |
|---|---|
| 0 | sukces, odpowiedź na stdout |
| 1 | błąd użycia albo błąd konfiguracji |
| 2 | brak wymaganego narzędzia (`jq`, `curl`) |
| 3 | żaden provider z łańcucha nie ma ustawionego sekretu |
| 4 | wszyscy providerzy z łańcucha zawiedli |

### Pułapka, na którą trafisz: tokeny myślenia zjadają budżet odpowiedzi

Wszystkie trzy modele w tej konfiguracji domyślnie „myślą", a **tokeny myślenia
liczą się jako tokeny wyjścia i wchodzą w `max_tokens`**. Dla modeli Gemini 3
myślenia **nie da się wyłączyć** — mówi to wprost dokumentacja Google
(„Reasoning cannot be turned off for Gemini 2.5 Pro or 3 models").

Skutek w praktyce: przy zbyt małym `max_tokens` dostajesz **HTTP 200 i pustą
odpowiedź** z `finish_reason=length`. Zmierzyłem to: `gemini-3.7-flash` na
pytanie „odpowiedz jednym słowem: OK" zużył **108 tokenów myślenia i 1 token
treści**. Przy `max_tokens: 16` odpowiedź wróciła pusta; przy 256 wróciło „OK".

Dlatego `max_tokens` w `providers.json` to 4096, a nie kilkaset, a `ai-call.sh`
przy pustej treści zgłasza to jawnie i podaje przyczynę zamiast udawać sukces.

`reasoning_effort` (`minimal`/`low`/`medium`/`high`) da się ustawić flagą
`--reasoning-effort`, ale to **ogranicza**, nie wyłącza: przy `low` i
`max_tokens: 64` model wciąż zużył 61 tokenów na myślenie i nie zdążył
odpowiedzieć.

## Jak to się mapuje na `github/gh-aw`

Plan przewiduje w Fazie 7 framework [`github/gh-aw`](https://github.github.com/gh-aw/)
(GitHub Agentic Workflows). Sprawdziłem jego dokumentację — providerzy z tej
warstwy mapują się na niego tak:

| Provider tutaj | Ścieżka w gh-aw | Uwagi |
|---|---|---|
| `gemini-flash`, `gemini-pro` | `engine: gemini` + sekret `GEMINI_API_KEY` | wbudowany silnik; alternatywnie bezkluczowe Google Workload Identity Federation (`engine.auth`), które przełącza silnik na backend Vertex AI |
| DeepSeek, OpenRouter | **brak wbudowanego silnika** | trasa obejściowa: `engine: copilot` w trybie BYOK, przez `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, `COPILOT_MODEL` i `COPILOT_PROVIDER_TYPE: openai` — czyli dokładnie te same trzy wartości co tutaj |

Wbudowane silniki gh-aw to `copilot`, `claude`, `codex`, `gemini` i `pi`.
DeepSeeka nie ma na tej liście. Dla samego silnika `gemini` własny endpoint
ustawia się zmienną `GEMINI_API_BASE_URL` w `engine.env`.

Mechanizmy bezpieczeństwa, na które gh-aw liczy (i które są powodem, dla którego
plan go wybrał): job agenta jest domyślnie **read-only i w sandboksie**, ruch
wychodzący przechodzi przez firewall z listą dozwolonych hostów, a zapisy do
GitHuba idą przez osobne, walidowane joby `safe-outputs` z wąskimi
uprawnieniami. Nie zmienia to zasady z góry tego dokumentu: nawet w gh-aw agent
proponuje, a bramką jest CI.

## Szablon workflow — wyłączony domyślnie

[`templates/ai-fix-build.yml`](templates/ai-fix-build.yml) to szablon do
skopiowania do repo docelowego. **Leży w `ai/templates/`, a nie w
`.github/workflows/`, więc sam z siebie nigdy się nie uruchomi.** Na tym etapie
jest opcjonalny i celowo nieaktywny — żadne repo go nie dostaje automatycznie.

Twarde założenia szablonu:

- `on: workflow_dispatch` — tylko ręczne uruchomienie, żadnego triggera z PR-a
  ani ze zdarzenia `workflow_run`,
- `permissions: contents: read` i nic więcej — brak `pull-requests: write`, brak
  jakiejkolwiek drogi do merge'a,
- `persist-credentials: false` w checkoucie. To nie kosmetyka: dokładnie tą
  ścieżką (`.git/config`) badacze wyprowadzili token z workflowa Gemini CLI
  Google'a i uzyskali push na `main`,
- wynik wychodzi jako **artefakt z patchem**, nie jako commit. Nałożenie patcha to
  osobna, świadoma decyzja człowieka albo osobny job z własnym tokenem.

## Aktualne identyfikatory modeli i koszty

Stan na 18.08.2026. Ceny za milion tokenów, w USD.

| Provider | Model | Wejście | Wyjście | Darmowy tier | Źródło |
|---|---|---|---|---|---|
| Gemini | `gemini-3.6-flash` | 1,50 | 7,50 | tak | [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| Gemini | `gemini-3.1-pro-preview` | 2,00 (4,00 >200k) | 12,00 (18,00 >200k) | **nie** | [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| DeepSeek | `deepseek-v4-flash` | 0,22 / 0,44 | 0,66 / 1,32 | nie | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| DeepSeek | `deepseek-v4-pro` | 0,66 / 1,32 | 1,98 / 3,96 | nie | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| OpenRouter | `google/gemini-3.7-flash` | 0,375 | 1,875 | nie | [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models) |

DeepSeek podaje dwie ceny, bo ma taryfę godzinową: pierwsza to poza szczytem,
druga w szczycie. Szczyt to 01:00–04:00 i 06:00–10:00 UTC. Trafienie w cache
wejściowy jest u niego skrajnie tanie (`$0,007`–`$0,014` za milion), co dla
agenta czytającego wielokrotnie ten sam log builda ma znaczenie.

### Dwie rzeczy, które warto wiedzieć o wersjach Gemini

**`gemini-3.7-flash` istnieje, ale nie wybrałem go jako domyślnego.** Widnieje w
cenniku Gemini Enterprise Agent Platform (Google Cloud) z ceną wprowadzającą
`$0,75 / $3,75` do 31.12.2026 i jest dostępny przez OpenRouter — sprawdziłem, że
odpowiada. Natomiast **na stronie cennika Gemini Developer API go nie ma**;
najnowszy Flash tam udokumentowany to `gemini-3.6-flash`. Skoro warstwa celuje w
Developer API (`generativelanguage.googleapis.com`), domyślnym jest ten, który
jest tam opisany. Gdy 3.7 pojawi się w cenniku Developer API, przełączenie to
zmiana jednego pola `model`.

**Darmowy tier obejmuje Flash, nie Pro.** Modele Pro zostały zdjęte z Free
01.04.2026. Free ma też niższe limity (rzędu kilku–kilkunastu zapytań na minutę)
i — istotne — **treść z darmowego tieru jest używana do ulepszania produktów
Google**, czego cennik nie ukrywa. Dla agenta czytającego logi buildów z
prywatnych repo to argument za płatnym tierem, nie za darmowym.

## Co zostało potwierdzone empirycznie, a co nie

Testy wykonane 18.08.2026 na tym skrypcie i tej konfiguracji. Klucze
`DEEPSEEK_API_KEY` i `OPENROUTER_API_KEY` były dostępne w środowisku, klucza
Gemini **nie było**.

### Potwierdzone

| Co | Wynik |
|---|---|
| DeepSeek `deepseek-v4-flash`, `https://api.deepseek.com/chat/completions` | HTTP 200, poprawna treść |
| DeepSeek zgodny z formatem OpenAI | tak — ten sam kod, co dla pozostałych |
| OpenRouter `https://openrouter.ai/api/v1/chat/completions` | HTTP 200, poprawna treść |
| Przełączenie providera bez zmiany kodu | tak, trzema drogami: flagą `-p`, zmienną `AI_PROVIDERS_CONFIG`, edycją `.lancuch.domyslny` |
| Automatyczne zejście na zapas | tak — przy braku `GEMINI_API_KEY` łańcuch pominął oba wpisy Gemini i odpowiedział z DeepSeeka |
| Klucz nie pojawia się w `ps -Ao args` | potwierdzone w trakcie żywego wywołania |
| Klucz nie pojawia się w komunikacie błędu | potwierdzone podstawionym fałszywym kluczem |
| Endpoint `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` istnieje i odpowiada | tak — z nieprawidłowym kluczem zwraca HTTP 400 „Please pass a valid API key", czyli host i ścieżka są poprawne |
| Kody wyjścia 1, 3 i 4 | wywołane celowo i zgodne z dokumentacją powyżej |
| Tokeny myślenia zjadają `max_tokens` | zmierzone: 108 tokenów myślenia na jednosłowną odpowiedź |
| `reasoning_effort: "none"` / wyłączenie myślenia dla Gemini 3 | **nie działa** — OpenRouter odpowiada HTTP 400 „Reasoning is mandatory for this endpoint and cannot be disabled", co zgadza się z dokumentacją Google |

### Niepotwierdzone i dlaczego

| Co | Dlaczego nie |
|---|---|
| Wywołanie `gemini-3.6-flash` **wprost** przez Gemini Developer API | brak `GEMINI_API_KEY` w środowisku. Endpoint potwierdzony, sam model nie. |
| Wywołanie `gemini-3.1-pro-preview` wprost przez Gemini Developer API | to samo — brak klucza |
| Poprawność identyfikatorów modeli Gemini u samego Google | potwierdzone **pośrednio**: oba modele odpowiedziały przez OpenRouter (`google/gemini-3.6-flash`, `google/gemini-3.1-pro-preview`), a `gemini-3.6-flash` figuruje dosłownie w przykładzie `curl` w dokumentacji Google. Bezpośrednio nie da się — `ListModels` bez klucza zwraca HTTP 403. |
| Limity darmowego tieru w liczbach (RPM/RPD) | Google podaje je per projekt w AI Studio, a nie jako stałą tabelę w dokumentacji. Liczby krążące po blogach (5–15 RPM, do 1000 zapytań dziennie) pochodzą ze źródeł wtórnych i ich nie potwierdzam. |
| Zachowanie szablonu workflow w GitHub Actions | nie uruchamiany — jest wyłączony i leży poza `.github/workflows/`. Sprawdzona wyłącznie poprawność składni YAML. |
| Integracja z `gh-aw` | nieuruchamiana. Mapowanie w tabeli wyżej pochodzi z dokumentacji gh-aw, nie z działającego workflow. |

**Pierwsza rzecz do zrobienia po zdobyciu klucza Gemini:**

```bash
export GEMINI_API_KEY=...   # nie wpisuj do żadnego pliku w repo
ai/scripts/ai-call.sh --check                      # powinno pokazać "tak"
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh --no-escalate
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh --escalate --no-escalate
```

Pierwsze wywołanie weryfikuje Flasha, drugie Pro. Jeśli któreś zwróci HTTP 404
albo błąd o nieznanym modelu, poprawną nazwę modelu znajdziesz w cenniku
Developer API i zmieniasz ją w `providers.json` — nic więcej.
