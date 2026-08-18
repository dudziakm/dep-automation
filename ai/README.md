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
echo "$PROMPT" | ai/scripts/ai-call.sh -p openrouter

# 2. Na całą sesję albo joba CI, bez dotykania repo:
AI_PROVIDERS_CONFIG=/sciezka/do/wlasnego-providers.json ai/scripts/ai-call.sh ...

# 3. Na stałe: zmień .lancuch.domyslny w ai/providers.json i scal PR-a.
```

## Łańcuch: DeepSeek Flash → DeepSeek Pro → OpenRouter

| Rola | Provider | Model | Kiedy wchodzi |
|---|---|---|---|
| domyślny | `deepseek` | `deepseek-v4-flash` | każde pierwsze podejście |
| eskalacja | `deepseek-pro` | `deepseek-v4-pro` | trudniejszy przypadek, albo gdy Flash zawiódł |
| zapas | `openrouter` | `google/gemini-3.7-flash` | DeepSeek niedostępny: 401, 429, 5xx, awaria dostawcy |
| przewidziany, **wyłączony** | `gemini-flash` | `gemini-3.6-flash` | dopiero gdy pojawi się `GEMINI_API_KEY` |
| przewidziany, **wyłączony** | `gemini-pro` | `gemini-3.1-pro-preview` | jak wyżej, jako eskalacja po włączeniu Gemini |

`ai-call.sh` przechodzi ten łańcuch automatycznie. Provider jest pomijany, gdy
brakuje jego sekretu albo gdy odpowiedź nie nadeszła. Eskalację można też wywołać
od razu:

```bash
# Od razu Pro, bo wiem, że przypadek jest trudny:
echo "$PROMPT" | ai/scripts/ai-call.sh --escalate

# Tylko domyślny, bez eskalacji i bez zapasu (np. gdy pilnuję kosztu):
echo "$PROMPT" | ai/scripts/ai-call.sh --no-escalate
```

### Dlaczego eskalacja została w DeepSeeku, a nie na OpenRouterze

Sprawdziłem to na żywo, a nie z pamięci. `GET https://api.deepseek.com/models`
zwraca **dokładnie dwa** modele: `deepseek-v4-flash` i `deepseek-v4-pro`. Próba
wywołania nieistniejącej nazwy potwierdza to komunikatem samego dostawcy:
„The supported API model names are deepseek-v4-pro or deepseek-v4-flash".
`deepseek-v4-pro` odpowiada poprawnie (HTTP 200) i jest **realnie mocniejszym
wariantem tej samej rodziny** — kosztuje trzykrotnie więcej i ma pięciokrotnie
niższy limit współbieżności (500 wobec 2500), co jest wprost sygnałem, że to
model o innym profilu obliczeniowym, a nie ten sam pod inną nazwą.

Dlatego eskalacja to `deepseek-pro`, a nie OpenRouter. Trzy powody:

1. **Eskalacja ma zmieniać moc modelu, nie dostawcę.** Zmiana dostawcy zmienia
   naraz zbyt wiele: model, tokenizer, sposób obsługi myślenia i zachowanie przy
   długim wejściu. Gdyby eskalacja szła od razu na innego dostawcę, nie dałoby
   się powiedzieć, czy poprawa wyniku wynika z mocniejszego modelu, czy z
   przypadku.
2. **Eskalacja to zmiana jednego pola.** `deepseek` i `deepseek-pro` mają ten sam
   `base_url` i ten sam sekret — różnią się wyłącznie nazwą modelu. Nie trzeba do
   niej drugiego klucza, więc nie może się zepsuć na braku konfiguracji.
3. **OpenRouter ma inną robotę.** Jest odpowiedzią na pytanie „co, gdy DeepSeek
   nie odpowiada", a nie „co, gdy zadanie jest trudne". Awaria dostawcy i trudny
   przypadek to dwa różne problemy i nie powinny mieć jednego rozwiązania.

Gdyby okazało się, że Pro też nie daje rady, właściwym krokiem **nie** jest
kolejny model, a człowiek. Patrz akapit o pętlach niżej.

### Kiedy eskalować na Pro

Eskalacja jest trzykrotnie droższa: Pro to `$0,66 / $1,98` za milion tokenów
wejścia i wyjścia poza szczytem, wobec `$0,22 / $0,66` dla Flasha (w szczycie
odpowiednio `$1,32 / $3,96` i `$0,44 / $1,32`). W bezwzględnych liczbach to
nadal grosze, ale zasada zostaje ta sama:

- **Flash jest domyślny zawsze.** Typowa naprawa po podbiciu zależności to
  odczytanie loga `npm ci` albo `mvn verify` i jedna zmiana w manifeście. To nie
  wymaga mocniejszego modelu.
- **Pro tylko wtedy, gdy Flash nie dał rady**: zwrócił błąd, zwrócił pustą
  odpowiedź, albo jego propozycja nie przeszła bramki CI (i to CI stwierdziło, że
  nie przeszła — nie model).
- **Nie eskalujemy w pętli.** Jeden przebieg Flash, jeden Pro. Jeśli oba nie
  poradziły, sprawa idzie do człowieka. Pętla „próbuj dalej" to najprostszy
  sposób na niekontrolowany rachunek.

### Rola OpenRoutera

OpenRouter to **zapas na wypadek awarii, nie druga opinia**. Jest w łańcuchu, bo:

- to **niezależny dostawca i niezależny klucz** — awaria albo wyczerpany limit po
  stronie DeepSeeka go nie dotyka,
- jego API jest **zgodne z OpenAI** (potwierdzone empirycznie), więc nie wymaga
  ani jednej linii kodu więcej,
- daje **dostęp do modeli Gemini bez posiadania klucza Google** — co jest
  jedynym sposobem, w jaki Gemini bierze dziś udział w tej warstwie.

Świadoma wada, którą trzeba znać: OpenRouter dodaje **jeszcze jednego
pośrednika** w ścieżce, przez którą przechodzi treść cudzych changelogów
czytanych przez agenta. Przy agencie, którego głównym ryzykiem jest prompt
injection, każdy dodatkowy hop to dodatkowa powierzchnia. Dlatego jest zapasem, a
nie domyślnym.

### Rola Gemini — opisane, wyłączone, gotowe

`gemini-flash` i `gemini-pro` mają status `wyłączony` i **nie występują w
łańcuchu**. To decyzja, nie przeoczenie: nie ma klucza Google, a płatny tier
Gemini został na teraz odrzucony. Wpisy zostają, żeby włączenie było zmianą
konfiguracji, a nie nową robotą:

```bash
# 1. Dodaj sekret (nigdy do pliku w repo):
gh secret set GEMINI_API_KEY --repo dudziakm/dep-automation

# 2. W ai/providers.json: status "wyłączony" -> "aktywny" przy gemini-flash
#    i wpisz "gemini-flash" w .lancuch.domyslny (albo w .lancuch.zapas).
```

Uwaga na kolejność: CI pilnuje, żeby provider ze statusem `aktywny` **był** w
łańcuchu, a provider z łańcucha **był** aktywny. Zmiana samego statusu bez
dopisania do łańcucha (albo odwrotnie) zapali `validate ai layer` na czerwono —
celowo, bo to zawsze znaczy, że ktoś zrobił połowę roboty.

`ai-call.sh` pozwala użyć wyłączonego providera jawnie, ale wtedy głośno o tym
mówi:

```
$ ai/scripts/ai-call.sh -p gemini-flash
UWAGA: provider 'gemini-flash' ma w konfiguracji status 'wyłączony'. Uzywam go, bo zazadano go jawnie przez --provider.
```

## Sekrety

W konfiguracji trzymamy **wyłącznie nazwy** zmiennych. Wartości nigdy nie trafiają
do repo.

| Sekret | Dla kogo | Skąd wziąć | Wymagany |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | `deepseek`, `deepseek-pro` | [platform.deepseek.com](https://platform.deepseek.com/) | tak — to domyślna ścieżka i eskalacja |
| `OPENROUTER_API_KEY` | `openrouter` | [openrouter.ai/keys](https://openrouter.ai/keys) | zalecany — zapas na awarię DeepSeeka |
| `GEMINI_API_KEY` | `gemini-flash`, `gemini-pro` | [Google AI Studio](https://aistudio.google.com/apikey) | nie — Gemini jest wyłączone |

Jeden klucz DeepSeeka obsługuje i domyślnego providera, i eskalację: `deepseek` i
`deepseek-pro` mają ten sam `base_url` i ten sam sekret.

Jeśli kiedyś włączysz Gemini: klucze generowane w AI Studio są domyślnie
ograniczone do Gemini API, ale klucz z Google Cloud Console trzeba ograniczyć
ręcznie do `generativelanguage.googleapis.com` — od 19.06.2026 Gemini API odrzuca
nieograniczone klucze. *(Źródło: komunikat na forum Google AI Developers,
powtarzany w wielu wątkach; nie znalazłem go na stronie dokumentacji, więc
traktuj jako niepotwierdzone oficjalnym dokumentem.)*

## Gdzie mieszkają sekrety na koncie osobistym

To pytanie ma jedną niewygodną odpowiedź, więc podaję ją wprost, z dowodem.

### Nie ma sekretów Actions na poziomie konta osobistego

Dokumentacja GitHuba wymienia **trzy** poziomy sekretów Actions i ani jeden nie
jest poziomem użytkownika: „Secrets allow you to store sensitive information in
your **organization, repository, or repository environments**"
([docs](https://docs.github.com/en/actions/concepts/security/secrets)).
Współdzielenie jednego wpisu między repozytoriami daje **wyłącznie** poziom
organizacji, wraz z polityką dostępu wybierającą repozytoria.

Sprawdziłem to też na API, bo dokumentacja bywa niepełna. Różnica w kodach
odpowiedzi jest rozstrzygająca:

| Zapytanie | Odpowiedź | Co to znaczy |
|---|---|---|
| `GET /user/actions/secrets` | **404** Not Found, generyczny `documentation_url` | endpoint **nie istnieje** |
| `GET /users/dudziakm/actions/secrets` | **404** | to samo |
| `GET /user/codespaces/secrets` | **403** „Must have admin rights to Repository", z `documentation_url` wskazującym `rest/codespaces/secrets#list-secrets-for-the-authenticated-user` | endpoint **istnieje**, zabrakło tylko zakresu tokenu |

Czyli sekrety na poziomie użytkownika istnieją, ale **tylko dla Codespaces** —
i to inny magazyn, którego Actions nie czyta. Konto `dudziakm` to `type=User`
i nie należy do żadnej organizacji (sprawdzone: `GET /user/orgs` zwraca pustą
listę), więc poziom organizacyjny jest dziś niedostępny.

**Wniosek: na koncie osobistym nie da się współdzielić sekretu Actions między
repozytoriami inaczej niż przez założenie organizacji.** Alternatywa, którą warto
znać, żeby nie tracić na nią czasu: `secrets: inherit` w wywołaniach reusable
workflows **nie** jest obejściem — dziedziczy sekrety widoczne dla repozytorium
wywołującego, więc sekret nadal musi tam istnieć.

### Rekomendowany układ: jeden sekret w repo sterującym

```
dudziakm/dep-automation  (publiczne, repo sterujące)
├── secrets: DEEPSEEK_API_KEY, OPENROUTER_API_KEY   <- jedyne miejsce z kluczami
├── ai/                                             <- warstwa providerów
└── workflow agenta (na razie NIE wdrożony)          <- działa stąd, sięga do innych repo tokenem

pozostałe repozytoria
└── bez żadnego klucza AI
```

```bash
gh secret set DEEPSEEK_API_KEY   --repo dudziakm/dep-automation
gh secret set OPENROUTER_API_KEY --repo dudziakm/dep-automation
```

Klucz AI leży w jednym repo i tylko tam. Zamiast kopiować go do 100 repozytoriów,
kopiujemy **wywołania**: workflow agenta uruchamia się w `dep-automation`, a do
repozytorium docelowego zagląda tokenem.

### Token sięgający do innych repo — konkretne uprawnienia

Fine-grained PAT, nie klasyczny. Nazwy uprawnień poniżej to dokładnie te, które
GitHub wystawia w formularzu tworzenia tokenu:

| Uprawnienie | Poziom | Po co dokładnie |
|---|---|---|
| **Metadata** | Read | obowiązkowe, GitHub dobiera je sam do każdego innego uprawnienia repo |
| **Contents** | Read | checkout repozytorium docelowego, odczyt manifestów |
| **Actions** | Read | odczyt logu padniętego przebiegu (`gh run view --log-failed`) |

I nic więcej. W szczególności **nie** nadawaj:

- **Pull requests: Write** — agent nie ma prawa wystawiać ani komentować PR-ów.
  Dopóki wynik wychodzi jako artefakt, to uprawnienie jest zbędne.
- **Contents: Write** — brak zapisu to jedyna twarda gwarancja, że model nie
  dopisze niczego do `main`.
- **Checks** — akurat tu ograniczenie fine-grained PAT działa na naszą korzyść:
  taki token **nie potrafi** wołać Checks API
  ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens-limitations)),
  więc nie da się nim ustawić statusu, na którym opiera się decyzja o merge.

Zakres repozytoriów ustaw jako **Only select repositories** i wypisz konkretne, a
nie „All repositories". Token trzyma się na końcu w sekrecie repo sterującego, np.
`DEP_AGENT_TOKEN`, i wchodzi wyłącznie do kroku, który go potrzebuje.

### Rotacja i co się psuje, gdy token wygaśnie

- **Termin ważności**: od 1 do 366 dni; „no expiration" jest technicznie możliwe
  i **nie należy go wybierać**. Rozsądny cykl to 90 dni z przypomnieniem w
  kalendarzu — GitHub wysyła powiadomienie o zbliżającym się wygaśnięciu, ale
  trafia ono na maila, nie do CI.
- **Rotacja bez przestoju**: wygeneruj nowy token, `gh secret set DEP_AGENT_TOKEN
  --repo dudziakm/dep-automation` (nadpisuje w miejscu, workflow nie wymaga
  zmiany), sprawdź jednym ręcznym uruchomieniem, dopiero potem odwołaj stary.
  Kolejność jest istotna: sekrety są czytane w momencie **kolejkowania** przebiegu,
  więc przebieg już trwający dokończy się na starej wartości.
- **Gdy wygaśnie**: workflow agenta zaczyna dostawać `401 Bad credentials` na
  checkoucie repozytorium docelowego i **kończy się błędem**. To zachowanie
  akceptowalne, bo agent nie jest bramką — jego padnięcie nie blokuje ani nie
  przepuszcza żadnego PR-a. Nic nie „przechodzi po cichu"; po prostu nie ma
  diagnozy.
- **Odwołanie z zaskoczenia**: GitHub sam usuwa tokeny nieużywane od roku, a
  fine-grained PAT wypchnięty do publicznego repo albo gista jest **odwoływany
  automatycznie**. Drugi punkt jest realnym ryzykiem, bo `dep-automation` jest
  publiczne — dlatego token nigdy nie ma prawa trafić do pliku, tylko do sekretu.
- **Klucze AI rotuje się osobno**, u dostawców. To dwa niezależne cykle i nie ma
  sensu ich spinać.

### Wady tego układu, których nie zamierzam przemilczeć

1. **Token jest przywiązany do człowieka.** Fine-grained PAT należy do konta
   `dudziakm` i „becomes inactive if the user loses access to the resource"
   ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)).
   Rozwiązaniem docelowym jest **GitHub App** — krótkożyciowe tokeny instalacji,
   niezależne od użytkownika. Plan i tak przewiduje App dla Renovate, więc ten
   sam mechanizm da się wykorzystać.
2. **Limit 50 fine-grained PAT-ów na konto** ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)).
   Przy jednym tokenie do tego zadania nieistotny, ale wyklucza wzorzec „token
   per repozytorium" dla 100 repo.
3. **Centralizacja to jeden punkt awarii i jeden punkt kompromitacji.** Kto
   uzyska prawo zapisu do `.github/workflows/` w `dep-automation`, ten uzyska
   dostęp do wszystkich sekretów tego repo. Dlatego warto trzymać na tym repo
   ochronę gałęzi `main` i przeglądać zmiany w workflowach ze szczególną uwagą.
4. **Minuty Actions liczą się dla repozytoriów prywatnych.** Konto Free ma 2000
   minut miesięcznie ([docs](https://docs.github.com/en/billing/reference/product-usage-included));
   przebiegi w repozytoriach publicznych są darmowe. Agent uruchamiany ręcznie i
   rzadko nie zbliży się do limitu, ale automat odpalany przy każdym padniętym
   buildzie w kilkudziesięciu prywatnych repo — już tak. To dodatkowy argument za
   `workflow_dispatch`.
5. **Repo sterujące jest publiczne.** Dla samej warstwy `ai/` to bez znaczenia,
   bo nie ma w niej sekretów (pilnuje tego CI), a przy okazji upraszcza szablon:
   drugi checkout `dudziakm/dep-automation` nie potrzebuje tokenu. Ale każdy
   prompt i każda ścieżka wpisana na stałe w workflow są publiczne — logi
   prywatnych repo nie mają prawa trafić do żadnego artefaktu tego repo.

### Kiedy warto jednak założyć organizację

Gdyby liczba miejsc potrzebujących klucza rosła, organizacja jest jedynym
mechanizmem, który daje **jeden wpis dla wielu repozytoriów** wraz z polityką
dostępu. Trzeba wiedzieć, co się przy tym traci: repozytoria trzeba przenieść,
a GitHub Free for organizations opisuje repozytoria prywatne jako mające
„limited feature set" ([docs](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)).
**Nie sprawdziłem empirycznie**, czy sekrety organizacyjne działają dla repo
prywatnych na darmowym planie organizacji — dokumentacja GitHuba nie wymienia
ich wśród funkcji zarezerwowanych dla planu Team, ale spotkałem źródła wtórne
twierdzące inaczej. Bez konta organizacyjnego nie umiem tego rozstrzygnąć, więc
zostawiam to jako otwarte, a nie jako fakt. Przy dwóch sekretach w jednym repo
ta decyzja jest i tak przedwczesna.

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

Wszystkie modele w tej konfiguracji domyślnie „myślą", a **tokeny myślenia liczą
się jako tokeny wyjścia i wchodzą w `max_tokens`**. Dotyczy to również DeepSeeka:
tryb myślenia jest u niego domyślny dla obu wariantów V4 (mówi to jego tabela
modeli). Dla modeli Gemini 3 myślenia **nie da się wyłączyć** — mówi to wprost
dokumentacja Google („Reasoning cannot be turned off for Gemini 2.5 Pro or 3
models").

Skutek w praktyce: przy zbyt małym `max_tokens` dostajesz **HTTP 200 i pustą
odpowiedź** z `finish_reason=length`. Zmierzone na żywo na tym skrypcie, na
pytaniu „odpowiedz dokładnie jednym słowem":

| Model | Tokeny myślenia | Tokeny odpowiedzi razem |
|---|---|---|
| `deepseek-v4-flash` | 42 | 51 |
| `deepseek-v4-pro` | 67 | 75 |
| `google/gemini-3.7-flash` przez OpenRouter | 124 | 131 |

Wcześniejszy pomiar na `gemini-3.7-flash` (108 tokenów myślenia na 1 token
treści) przy `max_tokens: 16` dał pustą odpowiedź, a przy 256 poprawną — czyli
jednosłowna odpowiedź potrafi kosztować dwa rzędy wielkości więcej tokenów, niż
sugeruje jej długość.

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
| `deepseek`, `deepseek-pro`, `openrouter` | **brak wbudowanego silnika** | trasa obejściowa: `engine: copilot` w trybie BYOK, przez `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, `COPILOT_MODEL` i `COPILOT_PROVIDER_TYPE: openai` — czyli dokładnie te same trzy wartości co tutaj |
| `gemini-flash`, `gemini-pro` | `engine: gemini` + sekret `GEMINI_API_KEY` | wbudowany silnik; alternatywnie bezkluczowe Google Workload Identity Federation (`engine.auth`), które przełącza silnik na backend Vertex AI |

Wbudowane silniki gh-aw to `copilot`, `claude`, `codex`, `gemini` i `pi`.
DeepSeeka nie ma na tej liście, więc **domyślny provider tej warstwy wymaga w
gh-aw trasy BYOK**, a nie wbudowanego silnika. To znany koszt decyzji o
DeepSeeku, nie niespodzianka — i akurat ten koszt jest niski, bo BYOK przyjmuje
te same trzy wartości (`base_url`, klucz, model), które i tak trzymamy w
`providers.json`. Dla samego silnika `gemini` własny endpoint ustawia się zmienną
`GEMINI_API_BASE_URL` w `engine.env`.

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

| Rola | Provider | Model | Wejście | Wyjście | Darmowy tier | Źródło |
|---|---|---|---|---|---|---|
| **domyślny** | DeepSeek | `deepseek-v4-flash` | 0,22 / 0,44 | 0,66 / 1,32 | nie | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| **eskalacja** | DeepSeek | `deepseek-v4-pro` | 0,66 / 1,32 | 1,98 / 3,96 | nie | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| **zapas** | OpenRouter | `google/gemini-3.7-flash` | 0,375 | 1,875 | nie | [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models) |
| wyłączony | Gemini | `gemini-3.6-flash` | 1,50 | 7,50 | tak | [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| wyłączony | Gemini | `gemini-3.1-pro-preview` | 2,00 (4,00 >200k) | 12,00 (18,00 >200k) | **nie** | [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing) |

DeepSeek podaje dwie ceny, bo ma taryfę godzinową: pierwsza to poza szczytem,
druga w szczycie. Szczyt to 01:00–04:00 i 06:00–10:00 UTC. Trafienie w cache
wejściowy jest u niego skrajnie tanie (`$0,007`–`$0,014` za milion dla Flasha,
`$0,022`–`$0,044` dla Pro), co dla agenta czytającego wielokrotnie ten sam log
builda ma znaczenie.

Zestawienie kosztów, które uzasadnia wybór: domyślny model tej warstwy jest
**około siedmiokrotnie tańszy na wejściu i ponad jedenastokrotnie na wyjściu** od
`gemini-3.6-flash`, który był domyślny w poprzedniej wersji. Cały łańcuch —
Flash, Pro i zapas — mieści się poniżej ceny samego Gemini Flasha.

Ceny DeepSeeka i OpenRoutera pobrałem ze źródeł nadających się do sprawdzenia
maszynowo: tabela DeepSeeka ze strony cennika, cena OpenRoutera wprost z
`GET /api/v1/models` (`prompt = 0.000000375`, `completion = 0.000001875` za
token, czyli 0,375 i 1,875 za milion).

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

### Potwierdzone uruchomieniem

Cały łańcuch po zmianie na DeepSeeka został przejechany na żywo:

| Co | Wynik |
|---|---|
| **Wywołanie domyślne, bez żadnych flag** | `provider=deepseek model=deepseek-v4-flash`, HTTP 200, poprawna treść, `exit 0` |
| **`--escalate`** | `provider=deepseek-pro model=deepseek-v4-pro`, HTTP 200, poprawna treść, `exit 0` |
| **Zejście na zapas przy awarii DeepSeeka** | podstawiony nieprawidłowy `DEEPSEEK_API_KEY`: oba wpisy DeepSeeka odpadły na HTTP 401, `openrouter` odpowiedział poprawnie, `exit 0` |
| **Fail-closed przy braku wszystkich kluczy** | `exit 3` z komunikatem, nigdy `exit 0` |
| **Kontrola pozytywna tego samego testu** | z kluczami to samo wywołanie kończy się `exit 0` i zwraca treść — czyli test 3 mierzy brak kluczy, a nie coś innego |
| Lista modeli DeepSeeka | `GET https://api.deepseek.com/models` → HTTP 200, dokładnie dwa: `deepseek-v4-flash`, `deepseek-v4-pro` |
| Brak trzeciego, mocniejszego modelu DeepSeeka | próba `deepseek-v4`, `deepseek-v4-pro-thinking` → HTTP 400 z komunikatem dostawcy wymieniającym wyłącznie tę dwójkę |
| Stare aliasy `deepseek-chat` i `deepseek-reasoner` | nadal przyjmowane, ale **oba mapują się na `deepseek-v4-flash`** (widać w polu `model` odpowiedzi) — dlatego w konfiguracji są nazwy kanoniczne |
| OpenRouter `https://openrouter.ai/api/v1/chat/completions` | HTTP 200, poprawna treść, model `google/gemini-3.7-flash` |
| Zgodność wszystkich trzech aktywnych wpisów z formatem OpenAI | tak — ten sam kod bez ani jednej gałęzi per provider |
| Przełączenie providera bez zmiany kodu | tak, trzema drogami: flagą `-p`, zmienną `AI_PROVIDERS_CONFIG`, edycją `.lancuch.domyslny` |
| Klucz nie pojawia się w `ps -Ao args` | potwierdzone w trakcie żywego wywołania |
| Klucz nie pojawia się w komunikacie błędu | podstawiony fałszywy klucz: **0 wystąpień** w całym wyjściu, mimo dwóch komunikatów o błędzie autoryzacji |
| Endpoint `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` istnieje i odpowiada | tak — z nieprawidłowym kluczem zwraca HTTP 400 „Please pass a valid API key", czyli host i ścieżka są poprawne |
| Kody wyjścia 1, 3 i 4 | wywołane celowo i zgodne z dokumentacją powyżej |
| Tokeny myślenia zjadają `max_tokens` | zmierzone na obu modelach DeepSeeka i na Gemini przez OpenRouter — tabela wyżej |
| Nowe reguły w `validate-ai.yml` łapią regresję | test kontrolny na trzech celowo zepsutych konfiguracjach (domyślny na wyłączonego, aktywny poza łańcuchem, literówka w nazwie) — każda dała czerwień, stan faktyczny zielono |
| To samo **w prawdziwym CI**, nie tylko lokalnie | gałąź tymczasowa z domyślnym providerem wskazującym na wyłączone Gemini: przebieg `validate ai layer` zakończył się porażką z adnotacją „lancuch.domyslny wskazuje na 'gemini-flash', ktory ma status 'wyłączony' zamiast 'aktywny'". Gałąź usunięta po teście. |
| Brak sekretów Actions na poziomie konta osobistego | `GET /user/actions/secrets` → **404** (endpoint nie istnieje), `GET /user/codespaces/secrets` → **403** (istnieje, brak zakresu). Konto `dudziakm`: `type=User`, `GET /user/orgs` → pusta lista |
| `reasoning_effort: "none"` / wyłączenie myślenia dla Gemini 3 | **nie działa** — OpenRouter odpowiada HTTP 400 „Reasoning is mandatory for this endpoint and cannot be disabled", co zgadza się z dokumentacją Google |

### Niepotwierdzone i dlaczego

| Co | Dlaczego nie |
|---|---|
| Wywołanie `gemini-3.6-flash` **wprost** przez Gemini Developer API | **brak `GEMINI_API_KEY`.** Endpoint potwierdzony, sam model nie. Gemini pozostaje w konfiguracji jako wyłączone właśnie dlatego. |
| Wywołanie `gemini-3.1-pro-preview` wprost przez Gemini Developer API | to samo — brak klucza |
| Poprawność identyfikatorów modeli Gemini u samego Google | potwierdzone **pośrednio**: oba modele odpowiedziały przez OpenRouter (`google/gemini-3.6-flash`, `google/gemini-3.1-pro-preview`), a `gemini-3.6-flash` figuruje dosłownie w przykładzie `curl` w dokumentacji Google. Bezpośrednio nie da się — `ListModels` bez klucza zwraca HTTP 403. |
| Czy `deepseek-v4-pro` realnie **lepiej naprawia buildy** niż Flash | potwierdziłem, że istnieje, odpowiada i jest inaczej wyceniony oraz inaczej limitowany. Że daje lepsze naprawy — nie; do tego trzeba serii prawdziwych padniętych buildów, a nie jednego pytania kontrolnego. |
| Limity darmowego tieru Gemini w liczbach (RPM/RPD) | Google podaje je per projekt w AI Studio, a nie jako stałą tabelę w dokumentacji. Liczby krążące po blogach (5–15 RPM, do 1000 zapytań dziennie) pochodzą ze źródeł wtórnych i ich nie potwierdzam. |
| Czy sekrety organizacyjne działają dla repo prywatnych na darmowym planie organizacji | brak konta organizacyjnego, na którym mógłbym to sprawdzić. Dokumentacja GitHuba nie wymienia ich wśród funkcji tylko-dla-Team, źródła wtórne twierdzą inaczej. |
| Zachowanie szablonu workflow w GitHub Actions | nie uruchamiany — jest wyłączony i leży poza `.github/workflows/`. Sprawdzona wyłącznie poprawność składni YAML. |
| Integracja z `gh-aw` | nieuruchamiana. Mapowanie w tabeli wyżej pochodzi z dokumentacji gh-aw, nie z działającego workflow. |
| Zachowanie tokenu `DEP_AGENT_TOKEN` przy sięganiu do innych repo | żaden taki token nie został utworzony ani użyty. Zestaw uprawnień w sekcji o sekretach pochodzi z dokumentacji GitHuba i z listy uprawnień fine-grained PAT, nie z działającego przebiegu. |

**Pierwsza rzecz do zrobienia po zdobyciu klucza Gemini** — dopiero wtedy Gemini
przestaje być niepotwierdzone:

```bash
export GEMINI_API_KEY=...   # nie wpisuj do żadnego pliku w repo
ai/scripts/ai-call.sh --check -p gemini-flash
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh -p gemini-flash
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh -p gemini-pro
```

Flaga `-p` używa wpisu mimo statusu `wyłączony` i mówi o tym w logu — czyli da się
zweryfikować Gemini **bez** ruszania łańcucha. Jeśli któreś wywołanie zwróci HTTP
404 albo błąd o nieznanym modelu, poprawną nazwę znajdziesz w cenniku Developer
API i zmieniasz ją w `providers.json`. Dopiero gdy oba odpowiedzą, ma sens
przełączanie statusu na `aktywny` i wpisywanie Gemini do łańcucha.
