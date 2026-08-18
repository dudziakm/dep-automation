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
dostał poprawną odpowiedź z DeepSeeka (`api.deepseek.com`), z OpenRoutera
(`openrouter.ai`) i z Kimi (`api.moonshot.ai`), a przez OpenRouter także z modeli
Gemini. Szczegóły w sekcji „Co zostało potwierdzone empirycznie".

### Czwarta wartość, której wcześniej tu nie było: parametry

Dodanie Kimi pokazało granicę powyższej zasady i uczciwiej jest ją opisać niż
utrzymywać, że są zawsze trzy wartości. **Zgodność z protokołem nie oznacza
zgodności z parametrami.** Kimi ma `temperature` zablokowaną na `1.0` i odrzuca
każdą inną wartość:

```
HTTP 400: invalid temperature: only 1 is allowed for this model
```

Warstwa wysyłała dotąd `temperature: 0` dla wszystkich, więc Kimi nie
odpowiedziałby **ani razu**. Dlatego provider może dziś nadpisać dowolny
parametr własnym blokiem `parametry`, a `ai-call.sh` rozstrzyga je per provider:

```json
"kimi": {
  "model": "kimi-k2.7-code",
  "parametry": { "temperature": 1, "max_tokens": 16384 }
}
```

To nadal **zmiana danych, nie kodu** — ale wartości jest cztery, nie trzy.
Ograniczenie jest udokumentowane u dostawcy: `kimi-k2.7-code` i `kimi-k3` mają
`temperature` „fixed at `1.0`", a `kimi-k2.6` i `kimi-k2.5` `1.0` w trybie
myślenia i `0.6` poza nim ([Model Parameter
Reference](https://platform.kimi.ai/docs/api/models-overview)). Pozostali
providerzy nie mają bloku `parametry` i dostają dokładnie to, co dotąd —
sprawdziłem `--dry-run`, że nadal idzie do nich `temperature=0` i
`max_tokens=4096`.

### Jak przełączyć — trzy sposoby, od najmniej do najbardziej trwałego

```bash
# 1. Jednorazowo, na jedno wywołanie:
echo "$PROMPT" | ai/scripts/ai-call.sh -p openrouter

# 2. Na całą sesję albo joba CI, bez dotykania repo:
AI_PROVIDERS_CONFIG=/sciezka/do/wlasnego-providers.json ai/scripts/ai-call.sh ...

# 3. Na stałe: zmień .lancuch.domyslny w ai/providers.json i scal PR-a.
```

## Łańcuch: DeepSeek Flash → DeepSeek Pro → OpenRouter → Kimi

| Rola | Provider | Model | Kiedy wchodzi |
|---|---|---|---|
| domyślny | `deepseek` | `deepseek-v4-flash` | każde pierwsze podejście |
| eskalacja | `deepseek-pro` | `deepseek-v4-pro` | trudniejszy przypadek, albo gdy Flash zawiódł |
| zapas | `openrouter` | `google/gemini-3.7-flash` | DeepSeek niedostępny: 401, 429, 5xx, awaria dostawcy |
| zapas | `kimi` | `kimi-k2.7-code` | OpenRouter też nie odpowiedział — trzeci niezależny dostawca |

To jest **cała** lista: cztery wpisy, wszystkie aktywne, wszystkie w łańcuchu.
Nie ma tu providerów „przewidzianych na przyszłość" ani wyłączonych — wpis albo
działa i jest używany, albo go nie ma.

Rola w `lancuch` przyjmuje nazwę providera **albo listę nazw** próbowanych po
kolei — `"zapas": ["openrouter", "kimi"]`. Dopisanie kolejnego zapasu jest przez
to zmianą jednej linii w konfiguracji.

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

Warto zauważyć, że para Flash → Pro jest w tej warstwie **jedyną** parą „ten sam
dostawca, dwie moce" i nic tego nie zastąpi. Kimi nie nadaje się na eskalację
(inny dostawca, inny klucz — patrz akapit o Kimi niżej), OpenRouter tym bardziej.
Dlatego zasada z punktu 1 ma dokładnie jedno zastosowanie i jest nim ta para —
gdyby kiedyś zniknęła, eskalacja przestałaby mieć sens jako osobna rola, a nie
tylko zmieniłaby adresata.

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

### Rola Kimi — drugi zapas, i dlaczego akurat tam

```bash
# Kimi na żądanie, bez ruszania łańcucha:
echo "$PROMPT" | ai/scripts/ai-call.sh -p kimi
```

Kimi jest **drugim zapasem, po OpenRouterze** — nie domyślnym i nie eskalacją.
Trzy powody, w kolejności ważności:

1. **Limity konta wykluczają go z wczesnych ogniw.** Konto jest na najniższym
   progu cennika: **3 zapytania na minutę i współbieżność 1**
   ([Recharge and Rate Limiting](https://platform.kimi.ai/docs/pricing/limits)).
   Nie zmyśliłem tego z tabeli — dostałem to na żywo:
   `HTTP 429: request reached organization max RPM: 3`. Provider, który przyjmuje
   trzy zapytania na minutę pojedynczo, nie może stać na początku łańcucha
   odpalanego przy każdym padniętym buildzie.
2. **Dokłada trzeciego dostawcę i trzeci klucz — czyli dokładnie to, czego
   brakowało.** `deepseek` i `deepseek-pro` dzielą **jeden klucz i jeden host**,
   więc unieważniony klucz albo awaria `api.deepseek.com` wywala naraz domyślnego
   i eskalację. Dotąd ratował z tego wyłącznie OpenRouter, w pojedynkę. Kimi
   sprawia, że łańcuch ma trzy niezależne punkty awarii zamiast dwóch.
3. **Nie przestawia niczego, co już działa.** Kimi jest dopisany na **koniec**
   listy zapasów, więc każda dotychczasowa ścieżka wygląda co do znaku tak samo
   aż do miejsca, w którym łańcuch dotąd się poddawał. Domyślne wywołanie nadal
   idzie na DeepSeeka — sprawdzone uruchomieniem, nie założone.

**Dlaczego nie jako alternatywna eskalacja**, choć model jest wyspecjalizowany pod
kod: eskalacja w tej warstwie ma z definicji zmieniać **moc modelu przy tym samym
dostawcy** (uzasadnienie wyżej, w akapicie o `deepseek-pro`). Wstawienie tam
innego dostawcy zmieniałoby naraz model, tokenizer i obsługę myślenia, więc nie
dałoby się powiedzieć, czy lepszy wynik wziął się z trudniejszego modelu, czy ze
zmiany dostawcy. Do świadomego sięgnięcia po model kodowy jest flaga `-p kimi` —
i to jest właściwa droga, gdy ktoś *chce* Kimi, a nie gdy *wszystko inne padło*.

#### Który model Kimi i dlaczego — rozstrzygnięte pomiarem, nie przeczuciem

Konto widzi pięć modeli z rodziny Kimi. Wszystkie pięć **odpowiedziały** na realne
wywołanie czatu, więc sama dostępność niczego nie rozstrzyga. Rozstrzygnął test na
prawdziwym zadaniu tej warstwy: log `npm ci` z konfliktem peer dependency po
podbiciu `vite` z 5 na 7, `max_tokens: 4096`, prompt 378 tokenów.

| Model | Czas | Tokeny odpowiedzi | w tym myślenie | Wynik |
|---|---|---|---|---|
| `kimi-k2.5` | 131,5 s | 4096 | 4095 | **pusto** — `finish_reason=length` |
| `kimi-k2.6` | 57,7 s | 2058 | 1879 | poprawna diagnoza |
| **`kimi-k2.7-code`** | **18,8 s** | **600** | **463** | **poprawna diagnoza** |
| `kimi-k2.7-code-highspeed` | 17,4 s | 4096 | 4095 | **pusto** — `finish_reason=length` |
| `kimi-k3` | 17,7 s | 597 | 329 | poprawna diagnoza |

Ceny z oficjalnego cennika Moonshota, za milion tokenów, w USD, bez podatków:

| Model | Wejście (cache hit) | Wejście (cache miss) | Wyjście | Kontekst | Źródło |
|---|---|---|---|---|---|
| `kimi-k2.5` | 0,10 | 0,60 | 3,00 | 262 144 | [pricing/chat-k25](https://platform.kimi.ai/docs/pricing/chat-k25) |
| `kimi-k2.6` | 0,16 | 0,95 | 4,00 | 262 144 | [pricing/chat-k26](https://platform.kimi.ai/docs/pricing/chat-k26) |
| **`kimi-k2.7-code`** | **0,19** | **0,95** | **4,00** | **262 144** | [pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |
| `kimi-k2.7-code-highspeed` | 0,38 | 1,90 | 8,00 | 262 144 | [pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |
| `kimi-k3` | 0,30 | 3,00 | 15,00 | 1 048 576 | [pricing/chat-k3](https://platform.kimi.ai/docs/pricing/chat-k3) |

Wybrałem **`kimi-k2.7-code`**. Cztery argumenty, każdy z liczbą:

1. **Specjalizacja pod kod jest tu za darmo.** `kimi-k2.7-code` ma **identyczną
   cenę wejścia i wyjścia co ogólny `kimi-k2.6`** (0,95 / 4,00) — różnią się
   wyłącznie ceną trafienia w cache (0,19 wobec 0,16). Dostawca opisuje go jako
   „coding-focused model that completes programming tasks with higher success
   rates in long contexts". Skoro to samo kosztuje, a warstwa istnieje do czytania
   logów buildów, wybór modelu ogólnego byłby płaceniem tyle samo za mniej
   dopasowane narzędzie.
2. **Na prawdziwym zadaniu wyszedł najtaniej, mimo wyższej ceny jednostkowej niż
   K2.5.** Policzone ze zmierzonych tokenów i cen z tabeli (cache miss):
   `k2.7-code` **$0,00276**, `k2.6` $0,00859, `k3` $0,01034. Czyli jest **3,1×
   tańszy od K2.6 przy tej samej cenie za token** — bo zużył 3,4× mniej tokenów
   wyjścia na tę samą, poprawną odpowiedź.
3. **Najtańszy per token okazał się najdroższy per odpowiedź.** `kimi-k2.5` ma
   najniższy cennik (0,60 / 3,00), ale przepalił cały budżet 4096 tokenów na
   myślenie i **zwrócił pustkę**, płacąc przy tym $0,01252 — najwięcej z całej
   piątki, za zero treści. To dokładnie pułapka opisana niżej w akapicie o
   tokenach myślenia, tyle że zmierzona na Kimi.
4. **`kimi-k3` i wariant `-highspeed` odpadły na cenie, nie na jakości.** K3 dał
   równie dobrą odpowiedź, ale kosztuje **3,2× więcej na wejściu i 3,75× na
   wyjściu**, a jego przewaga — kontekst 1M tokenów — jest bez znaczenia przy
   logach builda mieszczących się w tysiącach tokenów. `-highspeed` to wprost
   **ten sam model** co `kimi-k2.7-code` („the same model as Kimi K2.7 Code, but
   with an output speed of approximately 180 Tokens/s"), sprzedawany **dokładnie
   dwa razy drożej** za samą szybkość. Agent CI działa w tle i nikt nie czeka na
   jego odpowiedź, więc płacenie 2× za latencję nie ma tu uzasadnienia.

#### Dlaczego `max_tokens` dla Kimi to 16384, a nie domyślne 4096

Bo `temperature` jest zablokowana na `1.0` i **nie da się jej zejść do zera**, więc
wyniki Kimi są z natury niepowtarzalne. Ten sam prompt puszczony na
`kimi-k2.7-code` siedem razy dał od **552 do 1336 tokenów myślenia** — rozrzut
2,4× przy identycznym wejściu.

Mówiąc uczciwie: **sam `kimi-k2.7-code` ani razu nie przekroczył 4096** w tych
siedmiu przebiegach. Podniesienie limitu to margines, nie łatka na zaobserwowaną
awarię. Uzasadniają go trzy rzeczy: ten sam model pod aliasem
`kimi-k2.7-code-highspeed` **wrócił pusty** przy 4096, `kimi-k2.5` zrobił to samo,
a mój log testowy miał 378 tokenów — prawdziwe logi padniętych buildów są
znacznie dłuższe, więc i myślenia będzie więcej. Przy tym `max_tokens` to
**limit, nie opłata**: płaci się za tokeny faktycznie wygenerowane, więc wyższy
sufit nie kosztuje nic, dopóki model z niego nie skorzysta.

#### Kiedy sięgać po Kimi zamiast DeepSeeka

Kimi **nie jest tańszy** i nie po to tu jest. Wobec domyślnego
`deepseek-v4-flash` (0,22 / 0,66 poza szczytem) kosztuje **4,3× więcej na wejściu
i 6× na wyjściu**. Sensowne powody, żeby po niego sięgnąć:

- **DeepSeek nie odpowiada i OpenRouter też** — wtedy nie trzeba nic robić, Kimi
  wejdzie sam jako ostatnie ogniwo łańcucha.
- **Zadanie jest wyraźnie kodowe i chcę modelu pod kod** — `-p kimi`. Typowo:
  długi log kompilacji, konflikt peer dependencies, migracja API między wersjami
  major.
- **W godzinach szczytu DeepSeeka różnica cen prawie znika.** Szczyt (01:00–04:00
  i 06:00–10:00 UTC) podwaja stawki DeepSeeka: `deepseek-v4-pro` kosztuje wtedy
  1,32 / 3,96, czyli **więcej na wejściu niż Kimi** (0,95) i praktycznie tyle samo
  na wyjściu (4,00). Jeśli eskalacja i tak wypada w szczycie, `-p kimi` jest
  porównywalny cenowo i daje model wyspecjalizowany pod kod.
- **Chcę drugiej opinii od niezależnego dostawcy** — ale wtedy pamiętaj, że to
  nadal tylko propozycja. Bramką są checki CI, nigdy zgodność dwóch modeli.

Czego Kimi **nie** rozwiązuje: nie jest szybszy (18,8 s wobec ułamków sekundy
DeepSeeka na tym samym pytaniu kontrolnym), nie jest tańszy i przy 3 zapytaniach
na minutę nie nadaje się do niczego zbiorczego. Podniesienie limitów wymaga
wyższego progu doładowania, nie zmiany w tym repo.

### Dlaczego nie ma Gemini jako providera

Gemini **nie jest** providerem tej warstwy i wpisy `gemini-flash` oraz
`gemini-pro` zostały z konfiguracji usunięte razem z sekretem
`GEMINI_API_KEY`. Powód jest finansowy, nie techniczny: dostępny klucz Google
siedzi na **darmowym tierze**, a wejście na płatny to wydatek rzędu 40 zł, na
który nie ma zgody.

To nie jest domysł — darmowy tier został zmierzony tym kluczem i wynik jest
jednoznaczny:

| Model | Odpowiedź | Co to znaczy |
|---|---|---|
| `gemini-3.6-flash` | **HTTP 200** | Flash na darmowym tierze działa |
| `gemini-3.1-pro-preview` | **HTTP 429**, metryki z sufiksem `-FreeTier` i `limit: 0` | Pro ma na tym koncie **zerowy przydział** — nie „mały", tylko żaden |

Czyli darmowy tier dawał **połowę** tego, czego warstwa potrzebuje: model
podstawowy owszem, ale mocniejszy wariant do eskalacji miał limit zero.
Provider, którego eskalacja nie może się nigdy wykonać, jest gorszy niż jego
brak, bo wygląda na dostępny i wywraca się dopiero w locie. Zgadza się to z
cennikiem Google: modele Pro zostały zdjęte z darmowego tieru 01.04.2026.

Jest jeszcze drugi powód, żeby nie ratować się tu darmowym tierem, i on nie
zniknąłby nawet przy limicie większym od zera: **treść wysłana na darmowy tier
jest używana do ulepszania produktów Google**, czego cennik nie ukrywa. Agent tej
warstwy czyta logi buildów z prywatnych repozytoriów, więc darmowy tier był dla
niego złym pomysłem niezależnie od limitów.

**Gdyby ta decyzja się kiedyś zmieniła**, wraca się tu w trzech krokach —
i zaczyna od doładowania, bo bez niego Pro dalej będzie zwracać 429:

```bash
# 1. Płatny tier w Google AI Studio (bez tego gemini-3.1-pro-preview ma limit 0).
# 2. Sekret — nigdy do pliku w repo:
gh secret set GEMINI_API_KEY --repo dudziakm/dep-automation
# 3. Wpis w ai/providers.json z base_url https://generativelanguage.googleapis.com/v1beta/openai
#    i dopisanie nazwy do .lancuch — CI pilnuje, żeby jedno bez drugiego nie przeszło.
```

Ceny z ostatniego sprawdzenia, dla orientacji przy tej decyzji: `gemini-3.6-flash`
to 1,50 / 7,50 USD za milion tokenów wejścia i wyjścia, `gemini-3.1-pro-preview`
2,00 / 12,00 (i 4,00 / 18,00 powyżej 200 tys. tokenów wejścia) —
[cennik Gemini API](https://ai.google.dev/gemini-api/docs/pricing). Dla
porównania domyślny `deepseek-v4-flash` kosztuje 0,22 / 0,66 poza szczytem, więc
sam Gemini Flash jest od niego **około siedmiokrotnie droższy na wejściu i ponad
jedenastokrotnie na wyjściu**. Rezygnacja z Gemini nie jest więc wyłącznie
oszczędnością 40 zł na starcie.

Uwaga, gdyby wpis kiedyś wracał: CI pilnuje, żeby provider ze statusem `aktywny`
**był** w łańcuchu, a provider z łańcucha **był** aktywny. Zrobienie połowy roboty
zapali `validate ai layer` na czerwono — celowo.

Modele Gemini nadal biorą udział w tej warstwie, ale **wyłącznie przez
OpenRoutera** (`google/gemini-3.7-flash` jako pierwszy zapas). To inna droga,
inny klucz i inny rachunek — nie wymaga konta Google ani płatnego tieru Gemini.

## Sekrety

W konfiguracji trzymamy **wyłącznie nazwy** zmiennych. Wartości nigdy nie trafiają
do repo.

| Sekret | Dla kogo | Skąd wziąć | Wymagany |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | `deepseek`, `deepseek-pro` | [platform.deepseek.com](https://platform.deepseek.com/) | tak — to domyślna ścieżka i eskalacja |
| `OPENROUTER_API_KEY` | `openrouter` | [openrouter.ai/keys](https://openrouter.ai/keys) | zalecany — pierwszy zapas na awarię DeepSeeka |
| `KIMI_API_KEY` | `kimi` | [platform.moonshot.ai](https://platform.moonshot.ai/) | opcjonalny — drugi zapas; bez niego łańcuch po prostu kończy się na OpenRouterze |

Trzy sekrety, trzech dostawców, koniec listy. `GEMINI_API_KEY` **został usunięty**
z sekretów repozytorium razem z wpisami Gemini — powód wyżej.

Jeden klucz DeepSeeka obsługuje i domyślnego providera, i eskalację: `deepseek` i
`deepseek-pro` mają ten sam `base_url` i ten sam sekret. To wygoda, ale i słabość:
oba padają razem, gdy padnie klucz albo host. Właśnie dlatego zapasy — OpenRouter
i Kimi — mają **własne klucze u własnych dostawców**.

Klucz Kimi działa wyłącznie na hoście globalnym `api.moonshot.ai`. Ten sam klucz
na `api.moonshot.cn` dostaje HTTP 401, więc chińskiego hosta w konfiguracji nie
ma i nie powinno być.

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
├── secrets: DEEPSEEK_API_KEY, OPENROUTER_API_KEY,  <- jedyne miejsce z kluczami
│            KIMI_API_KEY
├── ai/                                             <- warstwa providerów
└── workflow agenta (na razie NIE wdrożony)          <- działa stąd, sięga do innych repo tokenem

pozostałe repozytoria
└── bez żadnego klucza AI
```

```bash
gh secret set DEEPSEEK_API_KEY   --repo dudziakm/dep-automation
gh secret set OPENROUTER_API_KEY --repo dudziakm/dep-automation
gh secret set KIMI_API_KEY       --repo dudziakm/dep-automation
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
| `deepseek`, `deepseek-pro`, `openrouter`, `kimi` | **brak wbudowanego silnika** | trasa obejściowa: `engine: copilot` w trybie BYOK, przez `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, `COPILOT_MODEL` i `COPILOT_PROVIDER_TYPE: openai` — czyli dokładnie te same trzy wartości co tutaj. Dla Kimi dochodzi czwarta sprawa: `temperature` musi zostać `1`, a tego ta trasa nie wystawia jako osobnego pola — **niesprawdzone**, czy da się je tam narzucić |

Wbudowane silniki gh-aw to `copilot`, `claude`, `codex`, `gemini` i `pi`.
**Żaden z czterech providerów tej warstwy nie jest na tej liście**, więc cała
warstwa wymaga w gh-aw trasy BYOK, a nie wbudowanego silnika. To znany koszt
podjętych decyzji, nie niespodzianka — i akurat niski, bo BYOK przyjmuje te same
trzy wartości (`base_url`, klucz, model), które i tak trzymamy w
`providers.json`.

Jedyny silnik wbudowany, po który ta warstwa mogłaby sięgnąć wprost, to `gemini`
— i właśnie z niego zrezygnowaliśmy z powodów opisanych wyżej. Warto to wiedzieć,
bo przy wdrażaniu gh-aw łatwo uznać wbudowany silnik za drogę na skróty; tutaj
byłaby to droga przez płatny tier Gemini.

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
| **zapas** | Kimi (Moonshot) | `kimi-k2.7-code` | 0,95 (0,19 cache hit) | 4,00 | nie | [platform.kimi.ai/docs/pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |

Cztery wiersze, cztery aktywne wpisy — tabela pokrywa się jeden do jednego z
`providers.json`. Żaden wiersz nie opisuje modelu, którego warstwa nie potrafi
dziś wywołać.

DeepSeek podaje dwie ceny, bo ma taryfę godzinową: pierwsza to poza szczytem,
druga w szczycie. Szczyt to 01:00–04:00 i 06:00–10:00 UTC. Trafienie w cache
wejściowy jest u niego skrajnie tanie (`$0,007`–`$0,014` za milion dla Flasha,
`$0,022`–`$0,044` dla Pro), co dla agenta czytającego wielokrotnie ten sam log
builda ma znaczenie.

Zestawienie kosztów, które uzasadnia wybór: domyślny `deepseek-v4-flash` jest
**około siedmiokrotnie tańszy na wejściu i ponad jedenastokrotnie na wyjściu** od
`gemini-3.6-flash`, który był domyślnym providerem w pierwszej wersji tej
warstwy. Ta różnica zdecydowała o przejściu na DeepSeeka i jest osobnym powodem —
obok kosztu doładowania — dla którego Gemini tu nie wróciło.

Ceny DeepSeeka i OpenRoutera pobrałem ze źródeł nadających się do sprawdzenia
maszynowo: tabela DeepSeeka ze strony cennika, cena OpenRoutera wprost z
`GET /api/v1/models` (`prompt = 0.000000375`, `completion = 0.000001875` za
token, czyli 0,375 i 1,875 za milion). Cennik Kimi wziąłem ze stron cennikowych
poszczególnych modeli na `platform.kimi.ai`, w wersji `.md` — nagłówki kolumn są
tam jawne (`Input Price (Cache Hit)`, `Input Price (Cache Miss)`, `Output
Price`), więc nie musiałem zgadywać, która liczba jest którą.

**Kimi jest najdroższym aktywnym wpisem w tej warstwie i to jest świadome.**
Kosztuje 4,3× więcej na wejściu i 6× więcej na wyjściu niż domyślny Flash. Płaci
się tu nie za cenę, tylko za niezależność od dwóch pozostałych dostawców — i
płaci się dopiero wtedy, gdy oba zawiodą, bo Kimi jest ostatnim ogniwem łańcucha.

## Co zostało potwierdzone empirycznie, a co nie

Testy wykonane 18.08.2026 na tym skrypcie i tej konfiguracji. Wszystkie trzy
klucze warstwy — `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY` i `KIMI_API_KEY` — były
dostępne w środowisku. Klucz Gemini był dostępny tylko na czas pomiaru darmowego
tieru, po którym Gemini zostało z warstwy usunięte.

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
| Zgodność wszystkich czterech aktywnych wpisów z formatem OpenAI | tak — ten sam kod bez ani jednej gałęzi per provider |
| Przełączenie providera bez zmiany kodu | tak, trzema drogami: flagą `-p`, zmienną `AI_PROVIDERS_CONFIG`, edycją `.lancuch.domyslny` |
| Klucz nie pojawia się w `ps -Ao args` | potwierdzone w trakcie żywego wywołania |
| Klucz nie pojawia się w komunikacie błędu | podstawiony fałszywy klucz: **0 wystąpień** w całym wyjściu, mimo dwóch komunikatów o błędzie autoryzacji |
| **Darmowy tier Gemini nie wystarcza tej warstwie** | kluczem z darmowego tieru: `gemini-3.6-flash` → HTTP 200, ale `gemini-3.1-pro-preview` → HTTP 429 z metrykami `-FreeTier` i `limit: 0`. Model do eskalacji miał **zerowy** przydział, więc Gemini zostało usunięte zamiast zostawione jako wyłączone |
| Kody wyjścia 1, 3 i 4 | wywołane celowo i zgodne z dokumentacją powyżej |
| Tokeny myślenia zjadają `max_tokens` | zmierzone na obu modelach DeepSeeka i na Gemini przez OpenRouter — tabela wyżej |
| Nowe reguły w `validate-ai.yml` łapią regresję | test kontrolny na trzech celowo zepsutych konfiguracjach (domyślny na wyłączonego, aktywny poza łańcuchem, literówka w nazwie) — każda dała czerwień, stan faktyczny zielono |
| **Kimi: klucz i host** | `GET https://api.moonshot.ai/v1/models` → HTTP 200, dwanaście modeli. Ten sam klucz na `api.moonshot.cn` → HTTP 401, dlatego w konfiguracji jest wyłącznie host globalny |
| **Kimi: wszystkie pięć modeli K2.5+ realnie odpowiada** | `kimi-k2.5`, `kimi-k2.6`, `kimi-k2.7-code`, `kimi-k2.7-code-highspeed`, `kimi-k3` — każdy HTTP 200 na wywołaniu czatu. Obecność na liście `/models` tego nie przesądzała, więc sprawdziłem każdy osobno |
| **Kimi odrzuca `temperature: 0`** | HTTP 400 „invalid temperature: only 1 is allowed for this model" na `k2.5`, `k2.6` i `k2.7-code`. Bez nadpisania parametru Kimi nie odpowiedziałby ani razu — to był realny błąd do naprawienia, nie kosmetyka |
| **Kimi: wybór modelu rozstrzygnięty na prawdziwym zadaniu** | log `npm ci` z konfliktem peer dependency po podbiciu `vite` 5→7. `k2.7-code` i `k3` dały poprawną diagnozę, `k2.6` też ale 3,4× większym kosztem tokenów, `k2.5` i `-highspeed` wróciły **puste** z `finish_reason=length` — tabela wyżej |
| **Kimi: limit 3 zapytań na minutę** | HTTP 429 „request reached organization max RPM: 3" na żywo, zgodnie z tabelą progów w cenniku |
| **Kimi: rozrzut tokenów myślenia** | siedem przebiegów tego samego promptu na `kimi-k2.7-code`: 552–1336 tokenów myślenia. `temperature` zablokowana na 1.0, więc powtarzalności nie da się wymusić |
| Domyślne wywołanie **nadal** idzie na DeepSeeka po dodaniu Kimi | bez flag: `provider=deepseek model=deepseek-v4-flash`, HTTP 200, `exit 0`. Sprawdzone właśnie po to, żeby nie okazało się, że dodanie zapasu po cichu przestawiło domyślnego |
| Pozostali providerzy nie dostali parametrów Kimi | `--dry-run`: `deepseek`, `deepseek-pro` i `openrouter` nadal `max_tokens=4096 temperature=0`, tylko `kimi` ma `16384` i `1` |
| `-p kimi` zwraca treść | HTTP 200, `finish=stop`, `exit 0` |
| Zejście po łańcuchu aż do Kimi | podstawione zepsute `DEEPSEEK_API_KEY` i `OPENROUTER_API_KEY`: trzy pierwsze wpisy odpadły na HTTP 401, `kimi` odpowiedział poprawnie, `exit 0` |
| Klucz Kimi nie pojawia się w komunikacie błędu | podstawiony fałszywy klucz: HTTP 401 „Invalid Authentication", **0 wystąpień** klucza w stdout i stderr, `exit 4` |
| Skaner wycieków w CI obejmuje format klucza Kimi | klucz pasuje do istniejącego wzorca `sk-[0-9a-zA-Z]{20,}`, więc reguła nie wymagała ani rozszerzania, ani osłabiania |
| Reguły `validate-ai.yml` łapią regresję — czternaście przypadków | krok walidacyjny wyjęty wprost z workflow i puszczony na czternastu wariantach konfiguracji. **Dwa miały przejść i przeszły**: stan faktyczny oraz nowy provider wyłączony i trzymany poza łańcuchem (to jest dozwolone). **Dwanaście miało zapalić czerwień i zapaliło**: Kimi wyłączony ale w łańcuchu, Kimi aktywny ale poza łańcuchem, usunięta cała rola `zapas` przy aktywnym OpenRouterze, literówka `kimmi` na liście, `lancuch.domyslny` i `lancuch.eskalacja` wskazujące na **usunięte** wpisy Gemini, brak `base_url`, `temperature` jako napis, `max_tokens` jako napis, nazwa providera ze spacją, provider wyłączony wpisany do łańcucha, provider aktywny poza łańcuchem |
| Reguły nie strzelają za szeroko | dwa przypadki zielone wyżej są tu istotniejsze od dwunastu czerwonych: gdyby reguła „aktywny musi być w łańcuchu" była napisana zbyt agresywnie, wywracałaby się na legalnym wyłączonym wpisie. Nie wywraca się |
| Usunięcie Gemini jest **kompletne** | `lancuch.domyslny = "gemini-flash"` i `lancuch.eskalacja = "gemini-pro"` dają teraz „wskazuje na nieistniejacego providera", a nie „ma status wyłączony" — czyli wpisów naprawdę nie ma w konfiguracji, a nie tylko są odstawione |
| Test kontrolny wykrył **realny błąd w nowej regule** | pierwsza wersja sprawdzenia „aktywny poza łańcuchem" miała błąd zasięgu w jq (`index(.key)` odnosiło `.key` do tablicy łańcucha, nie do wpisu providera) i wywracała się na **poprawnej** konfiguracji. Bez kontroli pozytywnej wszystkie pozostałe przypadki świeciłyby się na czerwono z niewłaściwego powodu |
| Reguły dla **list** w łańcuchu też działają w prawdziwym CI | dwa przebiegi na gałęzi tymczasowej, oba czerwone z właściwą adnotacją: literówka `"kimmi"` na liście zapasów → „lancuch.zapas wskazuje na nieistniejacego providera 'kimmi'", a Kimi aktywny po wyjęciu z listy → „providerzy ze statusem 'aktywny' poza lancuchem: kimi". To druga z tych reguł miała wcześniej błąd w jq, więc akurat jej nie chciałem zostawiać sprawdzonej wyłącznie lokalnie. Gałąź usunięta po teście. |
| Prawdziwe CI łapie regresję **po usunięciu Gemini** | kolejna gałąź tymczasowa z `lancuch.domyslny = "gemini-flash"`: przebieg `validate ai layer` czerwony z adnotacją „lancuch.domyslny wskazuje na **nieistniejacego** providera 'gemini-flash'". Treść komunikatu jest tu dowodem sama w sobie — gdyby wpis został tylko wyłączony zamiast usunięty, CI powiedziałoby „ma status 'wyłączony'". Gałąź usunięta po teście. |
| Brak sekretów Actions na poziomie konta osobistego | `GET /user/actions/secrets` → **404** (endpoint nie istnieje), `GET /user/codespaces/secrets` → **403** (istnieje, brak zakresu). Konto `dudziakm`: `type=User`, `GET /user/orgs` → pusta lista |
| `reasoning_effort: "none"` / wyłączenie myślenia dla Gemini 3 | **nie działa** — OpenRouter odpowiada HTTP 400 „Reasoning is mandatory for this endpoint and cannot be disabled", co zgadza się z dokumentacją Google |

### Niepotwierdzone i dlaczego

| Co | Dlaczego nie |
|---|---|
| Czy `deepseek-v4-pro` realnie **lepiej naprawia buildy** niż Flash | potwierdziłem, że istnieje, odpowiada i jest inaczej wyceniony oraz inaczej limitowany. Że daje lepsze naprawy — nie; do tego trzeba serii prawdziwych padniętych buildów, a nie jednego pytania kontrolnego. |
| Czy `kimi-k2.7-code` **realnie lepiej naprawia buildy** niż `kimi-k2.6` albo `kimi-k3` | to samo zastrzeżenie. Zmierzyłem koszt, czas i to, że wszystkie trzy dały **poprawną** diagnozę jednego przypadku. Wybór opieram na cenie za odpowiedź, zużyciu tokenów i deklarowanej specjalizacji dostawcy — **nie** na przewadze jakościowej, bo jednego zadania do tego nie wystarczy. |
| Czy `kimi-k2.5` i `-highspeed` są **trwale** gorsze, czy tylko trafiły na zły przebieg | `temperature` jest zablokowana na 1.0, więc wyniki są losowe, a każdy z nich puściłem na tym zadaniu **raz**. Puste odpowiedzi mogą być pechem, a nie własnością modelu. Do rozstrzygnięcia potrzeba serii, na którą limit 3 zapytań na minutę praktycznie nie pozwala. |
| Czy `max_tokens: 16384` dla Kimi jest **potrzebne** | `kimi-k2.7-code` w siedmiu przebiegach zmieścił się w 4096 z zapasem (maks. 1336 tokenów myślenia). Wyższy limit to margines na dłuższe logi i na zaobserwowany rozrzut, a nie odpowiedź na awarię tego konkretnego modelu. Nie kosztuje nic, dopóki nie zostanie wykorzystany. |
| Zachowanie Kimi na **prawdziwym** padniętym buildzie z prawdziwego repo | testowałem na ręcznie złożonym logu `npm ci` (378 tokenów). Realne logi są dłuższe i brudniejsze; ani czasy, ani zużycie tokenów nie muszą się przenieść jeden do jednego. |
| Czy trasa BYOK w `gh-aw` potrafi narzucić Kimi `temperature: 1` | mapowanie BYOK wystawia `base_url`, klucz i model. Nie znalazłem w dokumentacji pola na `temperature`, a samego `gh-aw` nie uruchamiałem — więc nie wiem, czy Kimi da się przez nie zawołać bez błędu HTTP 400. |
| Czy limity Kimi da się podnieść dla tego konta | tabela progów mówi, że limit rośnie z sumą doładowań (Tier1 przy $10 to 200 RPM). Nie doładowywałem konta, więc opieram się wyłącznie na cenniku. |
| Czy sekrety organizacyjne działają dla repo prywatnych na darmowym planie organizacji | brak konta organizacyjnego, na którym mógłbym to sprawdzić. Dokumentacja GitHuba nie wymienia ich wśród funkcji tylko-dla-Team, źródła wtórne twierdzą inaczej. |
| Zachowanie szablonu workflow w GitHub Actions | nie uruchamiany — jest wyłączony i leży poza `.github/workflows/`. Sprawdzona wyłącznie poprawność składni YAML. |
| Integracja z `gh-aw` | nieuruchamiana. Mapowanie w tabeli wyżej pochodzi z dokumentacji gh-aw, nie z działającego workflow. |
| Zachowanie tokenu `DEP_AGENT_TOKEN` przy sięganiu do innych repo | żaden taki token nie został utworzony ani użyty. Zestaw uprawnień w sekcji o sekretach pochodzi z dokumentacji GitHuba i z listy uprawnień fine-grained PAT, nie z działającego przebiegu. |

**Pierwsza rzecz do zrobienia po dopisaniu jakiegokolwiek nowego providera** —
dokładnie ta ścieżka wyłapała u Kimi blokadę `temperature`, zanim wpis trafił do
łańcucha:

```bash
export NOWY_API_KEY=...   # nie wpisuj do żadnego pliku w repo
ai/scripts/ai-call.sh --check
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh -p nowy
```

Flaga `-p` pozwala sprawdzić wpis **bez** ruszania łańcucha, więc weryfikacja
nowego providera nigdy nie musi przestawiać domyślnego. Jeśli wywołanie zwróci
HTTP 400, przeczytaj komunikat dosłownie: u Kimi to właśnie tam wyszło, że
`temperature: 0` jest odrzucane i że provider potrzebuje własnego bloku
`parametry`. Dopiero gdy `-p` zwraca treść, ma sens dopisywanie nazwy do
`.lancuch` — CI i tak nie przepuści połowicznej roboty w żadną stronę.
