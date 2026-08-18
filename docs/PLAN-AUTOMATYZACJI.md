# Bezobsługowa automatyzacja zależności — plan wykonawczy

> Dokument jest eksportem interaktywnego canvasu `plan-automatyzacji-repo.canvas.tsx` do Markdowna. Stan danych: 18.08.2026, eksport: 18.08.2026.

Konto `dudziakm`, stan na 18.08.2026. Plan uwzględnia Twoje decyzje: zostajemy na
GitHub Free, naprawiamy padające CI, obejmujemy też repo archiwalne, wykluczamy
10xDevs.

**Skrót stanu:** ~79 repo w zakresie · 64 wiszące PR-y · 13 PR-ów wystawionych ·
4 repo realnie zepsute, nie 16 · 39 repo bez CI · plan Free · Renovate jako
bramka · bez GitHub Pro.

Dane zebrane 2026-08-18 z konta GitHub `dudziakm` (REST + GraphQL), dry-run
Renovate 44.33.2 na `dudziakm/testBasketPw`, oraz analiza logów 14 padających
workflowów. Decyzje użytkownika: plan Free, naprawiamy CI, obejmujemy też repo
archiwalne, wykluczamy 10xDevs.

---

## Co jest już zrobione — 13 PR-ów czeka na Ciebie

Fazy 1, 1b i 2 są wykonane, plus konflikty peer. Każdy PR ma w opisie przyczynę,
zmianę i weryfikację, więc możesz je przejrzeć bez wracania do tej rozmowy.

| Faza | Repo | PR | Co robi |
|---|---|---|---|
| 1b | `testBasketPw` | #5 | usunięty override js-yaml, npm ci → 28 paczek |
| 1b | `code-reviewer` | #11 | usunięte overrides axios i js-yaml, npm ci → 54 paczki |
| 1b | `playwright-lum-project` | #5 | usunięty override js-yaml, npm ci → 32 paczki |
| 1 | `testPwSetup` | #2 | upload-artifact v3→v4, plus checkout i setup-node na v4 |
| 1 | `testPwSetupEnv` | #2 | upload-artifact v3→v4, plus checkout i setup-node na v4 |
| 1 | `playwrightMacka` | #2 | upload-artifact v3→v4, a potem trigger na ręczny — cel testów zniknął |
| 1 | `globalsQA-banking` | #2 | przywrócone bloki `on:` w dwóch workflowach |
| peer | `playwright-lum-project-cypress` | #25 | preprocessor cucumber 18→26, usunięty błąd składni, cypress-on-fix na konflikt wtyczek |
| peer | `coachingDocs` | #17 | migracja na Tailwind 4 przez `@tailwindcss/vite` — Astro 7 nie znosi `@astrojs/tailwind` |
| 2 | `dep-automation` | #1 | kontrola odniesień między presetami w CI — walidator ich nie sprawdza |
| 2 | `testPwSetup` | #3 | `renovate.json` → warstwa js (pilot) |
| 2 | `etsyTests` | #2 | `renovate.json` → warstwa jvm (pilot) |
| 2 | `syringe` | #1 | `renovate.json` → warstwa silent (pilot) |

### Wynik CI: naprawa workflowów potwierdzona na żywych przebiegach

`testPwSetup` i `testPwSetupEnv` — zielone. `globalsQA-banking` — zielone na
wszystkich trzech przeglądarkach, pierwszy raz od maja 2025. To nie były więc
repo z zepsutymi testami, tylko z zepsutą instalacją workflow.

`playwrightMacka` po naprawie wreszcie się uruchomił i pokazał prawdziwą
usterkę: `automationpractice.pl` odpowiada wprawdzie HTTP 200, ale wysyła 4,6 KB
strony „Redirecting…", w której nie ma ani jednego `login` — sklep, po którym
chodzą te testy, zniknął. Żadna zmiana selektora tego nie odzyska, więc trigger
zjechał na `workflow_dispatch`: testy zostają, ale repo nie wisi na czerwono i
nie pali minut.

### Znalezisko z ubocza, które zmienia projekt bramek: część zestawów E2E nie może być bramką

Na PR-ze `testBasketPw` `npm ci` przechodzi („added 27 packages"), czyli poprawka
działa, ale E2E pada w oczekiwaniu na baner cookies. Przyczyna nie jest po
stronie testu: `g2a.com` odpowiada **HTTP 403 „Access Denied"** na 365 bajtach
dla klienta, który nie jest realną przeglądarką. Runner GitHuba wychodzi z adresu
centrum danych, więc baner nigdy się nie renderuje.

**Konsekwencja dla planu: nie wolno tego repo dopuścić jako bramki automerge.**
Jego krok `npm ci` jest wiarygodnym sygnałem, krok E2E nie jest żadnym. Zestaw
celujący w komercyjny serwis z ochroną antybotową wymaga własnego runnera albo
innego celu — a dopóki go nie ma, jest źródłem szumu, nie dowodu.

### Jedna rzecz, której nie ruszyłem, bo to Twoja decyzja

`PicsImprove` był na liście jako „jednolinijkowa naprawa brakującego triggera".
Sprawdziłem historię pliku i **blok `on:` został zakomentowany celowo** — commit
z 05.12.2025 nazywa się wprost „Disable Netlify deployment workflow", dzień po
nieudanej próbie naprawy komendy Netlify CLI.

Przywrócenie triggera nie naprawiłoby błędu, tylko cofnęło decyzję: każdy merge
do `main` deployowałby na żywo i wpisywał `OPENAI_API_KEY` oraz
`OPENROUTER_API_KEY` do środowiska Netlify. Sekrety są w repo skonfigurowane,
więc to by zadziałało — i właśnie dlatego tego nie zrobiłem bez Ciebie.

---

## Najpilniejsze znalezisko: poprzednia runda łatek bezpieczeństwa zablokowała CI

### Najpierw korekta tego, co napisałem godzinę temu

Napisałem, że sześć wpisów w `overrides` przytrzymuje podatne wersje i nazwałem
to 41 podatnościami. **Ta ocena skutku była błędna**, i to w dobrą stronę.
Sprawdziłem lockfile: w `nord-fjord-rag-guide` pięć z tych pakietów — `hono`,
`tar`, `postcss`, `picomatch`, `brace-expansion` — **wcale nie ma w drzewie
zależności**. Te overrides są martwe. W `coachingDocs` pin `nanoid 3.3.17` nigdy
się nie stosuje, a zainstalowana wersja to już załatana 3.3.18.

Żadna z tych szóstki nie jest więc żywą podatnością. Co zostaje realne: martwy
pin jest **miną z opóźnionym zapłonem** — zacznie obowiązywać w dniu, w którym
któraś zależność wciągnie ten pakiet do drzewa, i wtedy cicho zainstaluje wersję
podatną.

### Druga korekta, tego samego dnia: „16 repo z rozjechanym lockfile" też było błędne

Fakt się broni: w każdym z 16 repo blok `overrides` jest w `package.json`, a w
`package-lock.json` nie ma go wcale — zero wpisów, we wszystkich szesnastu. Ale
**wniosek, który z tego wyciągnąłem, był zły**. Uznałem, że rozjazd oznacza
zepsute `npm ci`, i zaplanowałem naprawę 16 repo.

Zamiast wnioskować dalej z treści plików, zmierzyłem: czysty HEAD, odłożony
`node_modules`, `npm ci --dry-run` w każdym repo. **Realnie zepsute są cztery,
nie szesnaście. Siedem instaluje się bez zarzutu — z rozjazdem i wszystkim.**

Mechanizm, którego nie doceniłem: npm porównuje nie „czy overrides są zapisane",
a „czy drzewo z lockfile'a różni się od tego, co wymuszają overrides". Gdy pin
trafia w wersję, która i tak jest w drzewie — albo w pakiet, którego w drzewie
nie ma — nie ma rozjazdu do zgłoszenia. Dlatego `3rd-devs-my` z 27 overrides
przechodzi, a `playwright-lum-project` z dwoma nie.

### Pomiar zamiast wnioskowania — wynik per repo

Pomiar rozstrzygający, 18.08.2026, wieczór. Dla każdego repo: czysty HEAD,
odłożony `node_modules`, `npm ci --dry-run --ignore-scripts`. Bez tego pomiaru
wnioskowałem z zawartości plików i wyszło źle — patrz „Druga korekta" powyżej.

| Repo | npm ci na czystym HEAD | Co pokazał pomiar |
|---|---|---|
| `playwright-lum-project` | zepsute | EUSAGE — override js-yaml duplikuje bezpośrednią zależność |
| `coachingDocs` | zepsute | EUSAGE, ale pod nim astro 7 vs @astrojs/tailwind peer ≤5 |
| `jit-old-cypress` | zepsute | ERESOLVE — cypress-real-events 1.7.6 wymaga cypress ≤12, repo ma 15.18 |
| `playwright-lum-project-cypress` | zepsute | ERESOLVE — cucumber-preprocessor 18.0.6 wymaga cypress ≤13, repo ma 15.18 |
| `3rd-devs-my` | przechodzi | 27 overrides, 0 w lockfile — a npm ci i tak przechodzi |
| `nord-fjord-rag-guide` | przechodzi | 17 overrides, 0 w lockfile — npm ci przechodzi |
| `aidevsApiTasks` | przechodzi | npm ci przechodzi; padał tylko mój relock, nie repo |
| `CoachHomePage` | przechodzi | npm ci przechodzi |
| `api_ai_tracker` | przechodzi | npm ci przechodzi |
| `cypressTodo` | przechodzi | npm ci przechodzi |
| `cypress-play` | przechodzi | npm ci przechodzi |
| `todo_bmad` | nie dotyczy | brak `package-lock.json` — npm ci nie ma czego weryfikować |

Cztery zepsute repo rozpadają się na dwie różne przyczyny, a nie jedną. Tylko
`playwright-lum-project` poddaje się lekarstwu z pilotów. Trzy pozostałe to
konflikty peer-dependency, czyli osobna klasa roboty: trzeba wymienić pluginy,
nie usunąć override.

### Wpisy overrides nieobecne w lockfile

Audyt overrides, 18.08.2026. Wszystkie 16 repo z blokiem `overrides` sprawdzone
przez GitHub API; piny skonfrontowane z OSV; łańcuch przyczynowy i lekarstwo
odtworzone lokalnie na klonach `testBasketPw` i `code-reviewer`.

W canvasie to wykres poziomy. Wartości (liczba wpisów `overrides` w
`package.json`; odpowiednik w lockfile wynosi zero we wszystkich pozycjach):

| Repo | Wpisy w package.json |
|---|---|
| `3rd-devs-my` | 27 |
| `jit-old-cypress` | 29 |
| `nord-fjord-rag-guide` | 17 |
| `aidevsApiTasks` | 7 |
| `coachingDocs` | 6 |
| `playwright-lum-project-cypress` | 5 |
| pozostałe 10 repo | 13 |

Źródło: GitHub API, 18.08.2026. **Ten wykres pokazuje rozjazd, nie awarię — po
pomiarze wiemy, że to dwie różne rzeczy.**

### Druga usterka: lockfile'a nie da się po prostu przeliczyć

Oczywisty odruch to `npm install --package-lock-only`. Spróbowałem — i pada z
`EOVERRIDE`: „Override for js-yaml@^5.2.1 conflicts with direct dependency".

Powód: część overrides dotyczy pakietów, które są **jednocześnie bezpośrednimi
zależnościami**, i mają inny zapis wersji. npm tego nie przyjmuje. Więc CI nie
może zainstalować, a lockfile nie może się przeliczyć, dopóki nie usunie się
kolizji.

To jest zakleszczenie, nie pojedynczy błąd. Dlatego samo „podbij wersje" by tego
nie ruszyło.

### Lekarstwo — sprawdzone na trzech repo, nie wywnioskowane

Override na pakiet, który i tak jest bezpośrednią zależnością, jest
**nadmiarowy** — wersję kontrolujesz wprost w `dependencies`. Usunięcie takich
wpisów zdejmuje `EOVERRIDE`, pozwala przeliczyć lockfile i odblokowuje `npm ci`.

| Repo | Usunięty override | Przed | Po | Co się instaluje |
|---|---|---|---|---|
| `testBasketPw` | `js-yaml: 5.2.2` | npm ci → EUSAGE | npm ci → added 28 packages | js-yaml 5.2.3 — nowsza niż chciał override, czysta w OSV |
| `code-reviewer` | `axios: ^1.18.0, js-yaml: 4.3.1` | npm ci → EUSAGE | npm ci → added 54 packages | axios 1.19.0 i js-yaml 4.3.1 — obie czyste w OSV |
| `playwright-lum-project` | `js-yaml: 5.2.2` | npm ci → EUSAGE | npm ci → added 32 packages | js-yaml 5.2.3 — nowsza niż chciał override, czysta w OSV |

**Poprawka nie pogarsza wersji — sprawdziłem to osobno.** W `testBasketPw` i
`playwright-lum-project` override chciał `js-yaml 5.2.2`, a po usunięciu
instaluje się `5.2.3`, czyli nowsza. W `code-reviewer` `axios` wychodzi na
`1.19.0`, `js-yaml` zostaje na `4.3.1`. Każda z tych wersji jest czysta w OSV.
Nic nie tracimy, a `npm ci` wraca do życia.

### Czego świadomie nie zrobiłem: siedmiu kosmetycznych PR-ów

W siedmiu repo, które przechodzą `npm ci`, mój skrypt usunął po kilka martwych
wpisów `overrides`. Przywróciłem te pliki i nie wystawiłem PR-ów. Audyt OSV
pokazał, że żaden z tych pinów nie trzyma podatnej wersji, więc zmiana nie
dawałaby ani korzyści bezpieczeństwa, ani funkcjonalnej — tylko ruch w
działającym kodzie i siedem PR-ów do przeglądu. Martwe piny zostają w rejestrze
jako „mina z opóźnionym zapłonem", którą złapie stały check porównujący
overrides z lockfile.

### coachingDocs to wyjątek i nie jest jednolinijkowy

Tam po zdjęciu kolizji wychodzi prawdziwy konflikt: `@astrojs/tailwind 6.0.2` — a
to jest **najnowsza wersja** — deklaruje `peer astro: ^3 || ^4 || ^5`, natomiast
repo siedzi na `astro ^7.2.1`. Ten lockfile mógł powstać tylko przez
`--legacy-peer-deps` albo `--force`.

Naprawa to migracja integracji Tailwinda na `@tailwindcss/vite`, czyli godziny,
nie minuty. Dlatego wypada z fazy 1b i idzie do osobnego zadania.

### Co z tego wchodzi na stałe do polityki

Dwa weta dla automerge, oba będące własnością diffu, a nie wersji — więc Renovate
nie umie ich wyrazić i implementujemy je jako mały wymagany check czytający
`git diff`: PR ruszający blok `overrides` oraz PR, którego lockfile wprowadza
nazwę pakietu nieobecną wcześniej.

Plus jeden nowy check, którego wcześniej nie planowałem, a który wyłapałby całą
tę sytuację w dniu jej powstania: **porównanie `overrides` z `package.json` z tym,
co zapisane w lockfile**. Jedna linia `jq`. Nie broni przed awarią — bo rozjazd
sam z siebie awarii nie powoduje, czego właśnie się nauczyłem — ale odcina
martwe piny, zanim któryś ożyje.

---

## Dobra wiadomość: plan Free nie wymaga własnego gatekeepera

Sprawdziłem kod źródłowy Renovate i okazuje się, że **Renovate sam jest bramką**
i nie potrzebuje branch protection. Funkcja `getBranchStatus` czyta zarówno
combined status, jak i check-runs, i merguje wyłącznie przy stanie zielonym. Przy
zerowej liczbie checków GitHub zwraca `pending`, co Renovate mapuje na żółty i
**odmawia merge'a**. Domyślnie fail-closed.

To znaczy, że nie musimy pisać setek linii YAML-a, które same stałyby się
elementem krytycznym dla bezpieczeństwa. Ryzyko drogi Free spada z „średnie" do
„niskie".

> **Korekta:** napisałem tu wcześniej, że trzy ustawienia muszą „pozostać w
> domyślnych, bezpiecznych wartościach". Dla `platformAutomerge` to było błędne.
> Sprawdziłem w źródle Renovate — ta opcja ma **`default: true`**, czyli
> domyślnie Renovate zleca scalanie GitHubowi. To właśnie ta droga stoi za
> wszystkimi udokumentowanymi incydentami fail-open (#34967, #28601, #25750):
> natywny auto-merge GitHuba przy zerowej liczbie required checks. Ustawienie
> `platformAutomerge: false` jest więc **nadpisaniem**, nie zachowaniem
> domyślnym, i musi być zapisane jawnie. `ignoreTests: false` i
> `internalChecksAsSuccess: false` są faktycznie domyślne — trzymamy je jawnie
> tylko jako zapis intencji.

---

## Cztery korekty planu po playbookach JVM i JS/TS

### Pułapka: karencja w npm byłaby u Ciebie atrapą

`min-release-age` wymaga npm ≥ 11.10.0, a starszy npm **cicho je ignoruje**.
Sprawdziłem osiem Twoich workflowów: **żaden nie pinuje npm**, a `setup-node`
dostaje node 18, 20 lub 22 — wszystkie wożą npm poniżej 11.10.0.

Bez jednej dodatkowej linii druga warstwa karencji nie istnieje, a config wygląda
jakby istniała. To najgorszy rodzaj zabezpieczenia.

Poprawka to `npm install -g npm@latest` po `setup-node`, plus
`engines.npm: ">=11.10.0"` jako pas bezpieczeństwa. Do tego `globalsQA-banking-VS`
siedzi na node 18, który jest już po EOL.

### Upraszcza: cała gałąź Spring/OpenRewrite Cię nie dotyczy

Sprawdziłem wszystkie 7 pomów: **zero Springa, zero BOM-ów, zero**
`dependencyManagement`. To proste projekty Selenium/TestNG.

Odpada więc najdroższy element playbooka JVM: migracje Spring Boot 4, recepty
OpenRewrite i problem z ich dystrybucją za autoryzacją Code Genome Project. Dla
Twoich repo `mvn -B verify` jest pełną bramką, bo bez BOM-ów nie ma rozjazdu
„zielony build, fałszywa wersja".

Jedno zostaje do decyzji: `mdm-selenium` deklaruje Javę 1.8. Aktualny LTS to 25.
Migracja jest osobnym zadaniem i nigdy nie idzie automatem.

### Oszczędza minuty: 22 repo archiwalne — tryb cichy zamiast PR-ów

Chciałeś objąć archiwalne — i jest na to ustawienie lepsze niż sonda
buildowalności: `"mode": "silent"`. Renovate liczy aktualizacje i wypełnia
Dependency Dashboard, ale **nie tworzy branchy ani PR-ów**.

Masz pełną widoczność CVE i porzuconych paczek przy niemal zerowym zużyciu minut
Actions, a jeśli kiedyś wrócisz do któregoś repo, dashboard jest już gotowy. To
wprost zdejmuje presję z limitu 2 000 minut, który był największym ryzykiem
kosztowym.

Dorzucamy `abandonmentThreshold: "18 months"` — Renovate oznaczy paczki bez
wydania od półtora roku. W repo z 2016–2019 to będzie najciekawsza informacja, bo
mówi, gdzie przyszły CVE nie dostanie już fiksa z góry.

### Brakowało: trzy ustawienia, których nie miałem w configu

| Ustawienie | Dlaczego jest konieczne u Ciebie |
|---|---|
| `rangeStrategy: "update-lockfile"` | Twoje package.json używają zakresów `^`. Bez tego Renovate przepisuje zakres zamiast ruszyć lockfile i połowa podbić jest pozorna. To jest ustawienie, które w ogóle czyni te repo automatyzowalnymi. |
| grupa `playwright` | 20 repo na Playwrightcie. `@playwright/test`, `playwright`, `playwright-core` i tag obrazu Dockera muszą ruszać się razem, inaczej dostajesz błąd niezgodności wersji przeglądarki zamiast wyniku testu. |
| `knip --include unlisted` | wykrywa importy pakietów, których nie ma w package.json — dokładnie to psuje się, gdy podbicie usunie tranzytywkę, na której nieświadomie polegałeś. W Javie kompilator łapie to darmo, w JS nie. |

---

## Dwie dziury, których nie da się zamknąć konfiguracją

To jedyne realne ryzyko pozostałe w tym modelu. Oba wynikają z algorytmu
Renovate, nie z błędu, i oba mają to samo rozwiązanie.

| Dziura | Mechanizm | Skutek |
|---|---|---|
| Check `skipped` lub `neutral` liczy się jako sukces | Workflow, którego joby zostaną pominięte przez `if:` na poziomie joba, produkuje check-runy o wyniku `skipped` | branch staje się zielony i PR się merguje bez żadnej realnej weryfikacji |
| Wystarczy jeden zielony status z czegokolwiek | Renovate wymaga „co najmniej jednego zielonego checka nie-`renovate/`", a nie „Twoje testy przeszły" | sam status z Netlify, Vercela czy Codecova autoryzuje merge |

**Rozwiązanie: jeden minimalny, zawsze uruchamiany check.** Każde repo, w którym
włączamy automerge, dostaje jeden workflow, który **zawsze się wykonuje i nigdy
nie może zostać pominięty**. Kluczowe: żadnego `if:` na poziomie joba, bo to
natychmiast otwiera dziurę numer jeden.

To jest jednocześnie ta bramka, która dla repo z testami E2E zastępuje
uruchamianie testów — patrz sekcja niżej. I to samo rozwiązanie obsługuje 39
repo, które dziś nie mają żadnego workflowa, więc bez niego nigdy nie dostaną
automerge.

---

## Zakres po Twoich decyzjach

Ponieważ chcesz objąć także repo archiwalne, zakres rośnie z 61 do ~79. Wypadają
wyłącznie forki cudzych projektów i repo z 10xDevs.

| Miara | Wartość |
|---|---|
| Repo na koncie | 101 |
| W zakresie automatyzacji | 79 |
| Forki — wykluczone | 16 |
| 10xDevs — wykluczone | 4 |
| Prywatne wśród aktywnych | 44 |

| Grupa | Liczba | Traktowanie |
|---|---|---|
| Aktywne, z buildem lub testami | ~34 | pełny automerge patch+minor po dodaniu checka verify |
| Aktywne testy E2E na cudzych stronach | 27 | automerge na bramce kompilacyjnej, nie na testach |
| Archiwalne 2016–2019, objęte na Twoją prośbę | 22 | najpierw sonda „czy to się w ogóle buduje", potem decyzja per repo |
| Forki cudzych projektów | 16 | wykluczone — nie utrzymujesz w nich zależności |
| 10xDevs i pochodne | 4 | `10xCardsAstro`, `my10xCards`, `ai-concept-compass`, `ai-concept-compass-greenfield` |

### Ekosystemy w 61 aktywnych repo

| Ekosystem | Liczba repo |
|---|---|
| JS/TS (package.json) | 36 |
| Brak manifestu | 11 |
| Java / Maven | 7 |
| Python | 6 |
| Gradle | 1 |
| .NET | 1 |

Źródło: skan drzewa plików przez GitHub API, 18.08.2026. `learnPython` liczy się
w JS/TS i Gradle jednocześnie.

### 64 otwarte PR-y Dependabota, per repo

| Repo | Otwarte PR-y |
|---|---|
| `web-ideas` | 15 |
| `learnPython` | 8 |
| `playwright-lum-project-cypress` | 7 |
| `mdm-cypress` | 6 |
| `rag-course-guide` | 3 |
| `nord-fjord-rag-guide` | 3 |
| `jit-old-cypress` | 3 |
| `cypress-play` | 3 |
| pozostałe 11 repo | 13 |

Źródło: GitHub search `is:open is:pr author:app/dependabot user:dudziakm`,
18.08.2026.

---

## Stan CI po ponownym, pełnym przeliczeniu

### Druga korekta: liczba się zgadza, ale skład repo nie

Przeszedłem wszystkie 61 aktywnych repo i wziąłem najnowszy przebieg **pomijając
workflowy Dependabota**. Czerwonych jest 14 — tyle samo co w mojej pierwszej
diagnozie, ale **to częściowo inne repo**.

Doszły `coachingDocs`, `code-reviewer`, `testBasketPw`, `playwrightDevContainer`
i `fixerTests`. Wypadły te, które zdążyły się naprawić. `coachingDocs` nie było
na pierwszej liście, a jest czerwone od 13.08 — to była luka w moim pomiarze.

| Miara | Wartość |
|---|---|
| Repo z czerwonym CI | 14 |
| Repo z zielonym CI | 8 |
| Repo bez ŻADNEGO przebiegu CI | 39 |

**Najważniejsza liczba w tej sekcji to 39.** Tylko **22 z 61** aktywnych repo
mają w ogóle jakikolwiek przebieg CI. Pozostałe 39 nie mają żadnego workflowa.
Renovate jest fail-closed, więc tam **nigdy nic nie zmerguje automatycznie** — i
słusznie, bo nie ma czego sprawdzić. To znaczy, że faza 3 planu, czyli dodanie
minimalnego checka `verify`, nie jest szlifem na koniec, a warunkiem, żeby
automatyzacja objęła więcej niż jedną trzecią repo.

| Repo | Przyczyna | Nakład |
|---|---|---|
| `code-reviewer` | npm ci → EUSAGE; overrides axios i js-yaml duplikują bezpośrednie zależności | sprawdzone, 2 min |
| `testBasketPw` | npm ci → EUSAGE; override js-yaml duplikuje bezpośrednią zależność | sprawdzone, 2 min |
| `testPwSetup, testPwSetupEnv, playwrightMacka` | `actions/upload-artifact@v3` — GitHub failuje job w 4 sekundy | PR wystawiony |
| `PicsImprove` | blok `on:` zakomentowany CELOWO — commit „Disable Netlify deployment workflow", 05.12.2025 | nie ruszamy — decyzja Twoja |
| `globalsQA-banking` | brak klucza `on:` w playwright.yml i cross-browser.yml — wycięty edycją z web UI | PR wystawiony |
| `jit-old-cypress, playwright-lum-project-cypress` | cypress 15.18, a pluginy deklarują peer cypress ≤12 i ≤13 — lockfile z `--force` | wymiana pluginów, osobne zadanie |
| `coachingDocs` | npm ci → EUSAGE, ale głębiej: `@astrojs/tailwind 6.0.2` wspiera astro ≤5, a repo jest na astro 7 | godziny — migracja Tailwinda |
| `fixerTests` | BUILD FAILURE, 1 expectation failed — realnie padający test Javy | do zdiagnozowania |
| `playwrightDevContainer` | logi wygasły, przyczyna nieustalona | do zdiagnozowania |
| `tobaccoBasketPw, bingAiTests` | testują strony, które przestały istnieć | workflow_dispatch |
| `ai-concept-compass, 10xCardsAstro` | 10xDevs — poza zakresem | pomijamy |

### Kolejność napraw — najwięcej odblokowanych repo na jednostkę pracy

| Tier | Praca | Odblokowuje | Czas |
|---|---|---|---|
| 1 ✓ | `upload-artifact@v3` → `@v4`, ten sam diff trzy razy | 3 repo; dwa wróciły na zielone, trzecie ujawniło martwy cel testów | zrobione |
| 2 ✓ | usunąć nadmiarowe wpisy z `overrides` | code-reviewer, testBasketPw i playwright-lum-project — npm ci instaluje w każdym | zrobione |
| 3 ✓ | dodać brakujący klucz `on:` w dwóch workflowach | globalsQA-banking — zrobione, zielone na 3 przeglądarkach; PicsImprove pominięty, bo wyłączony celowo | zrobione |
| 4 | stały check porównujący `overrides` z lockfile | po pomiarze wiadomo, że rozjazd sam nie psuje npm ci — check ma łapać martwe piny, nie awarie | wchodzi z fazą 3 |
| 5 | diagnoza fixerTests i playwrightDevContainer | dwa nieznane przypadki; fixerTests to jedyny realnie padający test | godziny |
| 6 | migracja Tailwinda w `coachingDocs` (astro 7) | jedyna prawdziwa praca nad zależnościami w tej partii | godziny |
| 7 | przenieść tobaccoBasketPw i bingAiTests na `workflow_dispatch` | zdejmuje dwa trwale czerwone repo z tablicy; przepisywanie nic nie kupuje | ~5 min |

Uwaga do Twojej decyzji „naprawiamy testy naprawdę": tiery 1–4 to prawdziwe
naprawy i warto je zrobić. Ale `bingAiTests` testuje interfejs Bing Chat, którego
Microsoft już nie wystawia, a `tobaccoBasketPw` celuje w przebudowany
ploom.co.uk. Tam „naprawa" oznacza napisanie testów od zera przeciwko innemu
produktowi i nie daje żadnego sygnału o zależnościach.

---

## Bramka weryfikacyjna per typ repo

27 z 61 aktywnych repo to testy E2E uderzające w cudze strony. Ich wynik mówi
„ktoś zmienił swój frontend", nie „ta paczka coś zepsuła". Dla nich bramką jest
**kompilacja, nie wykonanie**.

| Typ repo | Bramka | Co wykrywa | Czas |
|---|---|---|---|
| Playwright E2E (20 repo) | `npm ci && tsc --noEmit && npx playwright test --list` | zmiany API, usunięte eksporty, złamane typy, błędny config | ~40 s |
| Cypress E2E (7 repo) | `npm ci && tsc --noEmit && cypress verify` | to samo plus spójność binarki | ~60 s |
| Aplikacja JS/TS | `npm ci && tsc --noEmit && lint && build && test` | pełna weryfikacja — automerge w pełni uzasadniony | 1–4 min |
| Java / Maven (7 repo) | `mvn -B verify` | kompilacja i testy — pełna bramka, bo w żadnym pomie nie ma BOM-ów | 2–6 min |
| Archiwalne bez buildu | brak automerge, tylko Dependency Dashboard | nic — automerge byłby ślepym zaufaniem do rejestru | — |

`playwright test --list` parsuje i kompiluje wszystkie spec-i oraz page objecty,
ale nie startuje przeglądarki — stąd szybkość i determinizm.

---

## Architektura

### Rdzeń: repo sterujące + centralny Renovate

Jedno prywatne repo `dep-automation` z własną GitHub App i
`renovatebot/github-action@v46.2.2` w matrycy: jeden job na repo, token
ograniczony do tego jednego repo. Polityka w jednym presecie, w każdym repo
czterolinijkowy `renovate.json` z `extends`.

Uprawnienia App: Checks, Commit statuses, Contents, Issues, Pull requests,
Workflows — wszystkie read+write; Administration i Dependabot alerts read;
Metadata read. Bez Administration Renovate nie wykryje dozwolonych metod merge.

Przetestowane: dry-run Renovate 44.33.2 na `testBasketPw` wykrył managery `npm` i
`github-actions`, wygenerowałby 5 branchy i Dependency Dashboard. Config przeszedł
`renovate-config-validator`.

### Fail-closed: kluczowe ustawienia bramki

| Ustawienie | Wartość | Dlaczego |
|---|---|---|
| `platformAutomerge` | `false` | usuwa GitHuba z decyzji o merge; jedyna bramka to ocena statusu przez Renovate |
| `ignoreTests` | `false` | `true` zwarłoby ocenę statusu do zielonego przed jakimkolwiek zapytaniem do API |
| `internalChecksAsSuccess` | `false` | zielony `renovate/stability-days` sam z siebie nie może zazielenić brancha |
| `automerge` w korzeniu | `false` | default-deny; automerge przyznaje wyłącznie jedna jawna reguła |
| `minimumReleaseAge` | `"7 days"` | złośliwe wersje z 2025 żyły godziny, nie tygodnie |
| `matchCurrentVersion` | `"!/^0/"` | paczki przed 1.0 mogą łamać API w minorze |

### Pułapka: znany otwarty bug, który trafi w ten config

Issue #45236 (otwarte, 12.08.2026): przy jakimkolwiek `minimumReleaseAge`
aktualizacje typu `digest`, `pinDigest` i `lockFileMaintenance` dostają check
`renovate/stability-days`, który wisi **wiecznie**, bo te typy nie mają release
timestamp. Blokuje się bezpiecznie, ale cicho i na zawsze.

Obejście wchodzi do presetu od pierwszego dnia:
`minimumReleaseAgeBehaviour: "timestamp-optional"` w regule dopasowanej do tych
trzech typów.

### Bezpieczeństwo: warstwy chroniące przed złośliwą paczką

| Kontrola | Konfiguracja | Rola |
|---|---|---|
| Karencja w Renovate | `minimumReleaseAge: "7 days"` | PR nie powstaje, dopóki wersja nie odleży swojego |
| Karencja w package managerze | `min-release-age=7` | preset Renovate zeruje karencję dla lockFileMaintenance i pin — trzeba to podszyć |
| Blokada skryptów instalacyjnych | `allowScripts` | npm 12 blokuje domyślnie; to zatrzymuje sam payload |
| Pinowanie akcji do SHA | `helpers:pinGitHubActionDigests` | przesunięty tag przestaje być cichą zmianą |
| Audyt workflowów | `zizmor` | template injection, nadmiarowe permissions |
| Nocny skan pinów w overrides | `api.osv.dev/v1/querybatch` | jedyna kontrola łapiąca override, który sam trzyma podatną wersję — Dependabot tego nie widzi |

**Nigdy nie auto-mergujemy** majorów, paczek przed 1.0, PR-ów bezpieczeństwa,
obrazów Dockera, `lockFileMaintenance`, ani niczego co rusza `.github/`. PR-y
bezpieczeństwa Renovate wymusza przez `force` i omijają wszystkie limity —
dlatego zawsze idą do człowieka.

### AI: agent, wyłącznie gdy build padnie

Agent nie otwiera PR-ów z podbiciami — to robi Renovate, taniej i
deterministycznie. Agent wchodzi tylko wtedy, gdy podbicie **zepsuło build**.
Framework: `github/gh-aw` z `engine: gemini`, bo agent jest tam domyślnie
read-only w sandboksie, z firewallem egress i osobnym jobem wykrywającym
zagrożenia.

**Trzy zasady, bez których to jest groźne:**

1. `persist-credentials: false` w checkoucie. Dokładnie tą ścieżką
   (`.git/config`) badacze wyprowadzili token z workflowa Gemini CLI Google'a i
   uzyskali push na main.
2. Rozdzielone uprawnienia: job agenta ma `contents: read` i oddaje patch jako
   artefakt; osobny job z tokenem App go nakłada.
3. PR-y napisane przez agenta **nigdy** nie auto-mergują. Twoim głównym ryzykiem
   nie jest złośliwy współpracownik, a zatruty changelog paczki, który agent
   przeczyta jako instrukcję.

---

## Jak szybko zniknie backlog 64 PR-ów

Renovate merguje maksymalnie dwa branche na repo na jedno uruchomienie — po
pierwszym merge'u przerywa pętlę i ponawia zadanie raz. Każdy merge stawia
pozostałe branche za bazą, więc są rebase'owane, dostają nowy commit i w tym
przebiegu są pomijane.

| Czynnik | Wpływ |
|---|---|
| Sufit merge'y | 2 na repo na uruchomienie Renovate |
| Realny czas drenażu 64 PR-ów | 1,5–2 dni przy uruchamianiu co godzinę |
| `prConcurrentLimit`, `prHourlyLimit` | nie pomagają — limitują tworzenie, nie mergowanie; podniesienie tylko powiększa backlog |
| Co faktycznie pomaga | częstsze uruchamianie (co 15–30 min) i niski `branchConcurrentLimit` (3–5) |
| `rebaseWhen: "conflicted"` | nie używać jako skrótu — może zmergować dwie zmiany nigdy nietestowane razem |

---

## Koszty

| Pozycja | Miesięcznie | Uwagi |
|---|---|---|
| GitHub | 0,00 USD | zostajemy na Free — Renovate jest bramką, Pro niepotrzebne |
| Renovate | 0,00 USD | self-hosted, AGPL, bez limitu repo |
| Gemini API — triage i naprawy | 2–6 USD | agent odpala się tylko przy padniętych buildach, modele Flash |
| OpenRouter — eskalacje | 1–3 USD | opcjonalne, kilka trudnych przypadków |
| Minuty Actions | 0,00 USD | przy 79 repo ~900–1 100 z 2 000 w limicie; do monitorowania |
| zizmor, OSV-Scanner, Trivy | 0,00 USD | open source |

| Miara | Wartość |
|---|---|
| Realny koszt miesięczny | 3–9 USD |
| Szacowane minuty Actions / 2 000 | ~750 |

**Korekta: limit minut przestał być wąskim gardłem.** Wcześniej szacowałem
~1 100 z 2 000 minut i nazywałem to realnym ograniczeniem. Przeniesienie 22 repo
archiwalnych na `mode: "silent"` zdejmuje z tego rachunku całą ich pulę — nie
powstają tam ani branche, ani PR-y, ani przebiegi CI. Zostaje **~700–800 minut**,
z komfortowym zapasem.

Dwa warunki bez zmian: bramki muszą być szybkie (`--list` zamiast pełnych
testów), a repo sterujące zostaje prywatne, żeby logi Renovate nie ujawniały
publicznie nazw i zależności Twoich 44 prywatnych repo.

> Uwaga eksportu: ten warunek został później zmieniony — repo `dep-automation`
> jest publiczne, żeby Renovate mógł pobierać presety. Patrz sekcja „Faza 2"
> poniżej, gdzie decyzja jest opisana wprost.

---

## Faza 2 zrobiona: polityka mieszka w jednym repo

Powstało publiczne repo [dudziakm/dep-automation](https://github.com/dudziakm/dep-automation)
z pięcioma presetami. Każde repo docelowe dostaje jednolinijkowy `renovate.json`,
więc 53 repo nie rozjadą się konfiguracyjnie. Publiczne świadomie: Renovate musi
umieć pobrać preset, a presety nie zawierają sekretów.

### Klasyfikacja 102 repo — skryptem, nie na oko

| Grupa | Ile | Co z nią robimy |
|---|---|---|
| js — aktywne | 33 | preset js |
| jvm — aktywne | 6 | preset jvm |
| mixed (JS + JVM) | 1 | preset mixed — learnPython |
| uśpione >12 mies. | 13 | preset silent: dashboard tak, PR-y nie |
| forki cudzych repo | 16 | pomijane, Renovate i tak je pomija |
| inny ekosystem (Python, C#) | 11 | poza zakresem, ale mają manifesty |
| bez manifestów | 17 | nic do aktualizowania |
| wykluczone / puste | 4 | 10x i pochodne, 2 puste repo |

Do automatyzacji wchodzi 53 repo. Skrypt `scripts/classify.sh` jest powtarzalny —
klasyfikacja to snapshot, nie źródło prawdy.

### Zachowanie configu zmierzone, nie założone

Uruchomiłem prawdziwy dry-run Renovate na czterech repo, po jednym z każdej
warstwy. Liczby poniżej to plan bota, nie moje szacunki.

| Repo | Warstwa | Co wykrył | Co by utworzył |
|---|---|---|---|
| `testPwSetup` | js | 7 zależności / 2 pliki | 2 gałęzie, w tym renovate/playwright |
| `etsyTests` | jvm | 13 zależności / 1 plik | 10 gałęzi — najgorszy przypadek |
| `coachingDocs` | js | 18 zależności / 2 pliki | 0 gałęzi — wszystko wstrzymane |
| `syringe` | silent | 8 zależności / 1 plik | 0 gałęzi, tylko dashboard |

Trzy rzeczy się potwierdziły: grupowanie działa (Playwright zamiast trzech
osobnych PR-ów), tryb cichy faktycznie nie tworzy gałęzi, a w `coachingDocs`
aktualizacje istnieją, ale są wstrzymane przez zgodę z dashboardu i karencję —
czyli dokładnie tak, jak zaprojektowane. Log potwierdza też, że hamulce
`prConcurrentLimit: 3` i `prHourlyLimit: 2` realnie się załączają, więc nawet
`etsyTests` z dziesięcioma gałęziami nie zaleje Cię PR-ami.

### Pułapka, na którą się nabrałem — i którą warto znać

Zwalidowałem presety `renovate-config-validator`-em i uznałem, że odniesienia
między nimi są sprawdzone. Nie były. **Walidator nie pobiera presetów wskazanych
przez `github>`** — config z celowo błędną nazwą `:nie-ma-takiego` przechodzi u
niego jako poprawny. Sprawdziłem to testem kontrolnym.

Znaczyłoby to, że zmiana nazwy pliku presetu przechodzi walidację, a wysypuje się
dopiero u bota — od razu we wszystkich podłączonych repo. Dlatego CI repo
sterującego ma osobny krok sprawdzający odniesienia po plikach, a prawdziwy test
rozwiązywania presetu robi się dry-runem Renovate. Tam błędna nazwa daje
`config-presets-invalid`.

### Jedyny krok, którego nie mogę zrobić za Ciebie

Instalacja aplikacji Renovate wymaga OAuth w przeglądarce:
[github.com/apps/renovate](https://github.com/apps/renovate). Kolejność ma
znaczenie — **najpierw scal PR-y z configiem, potem instaluj**. Renovate wykrywa
istniejący `renovate.json` i pomija onboarding; bez tego dostaniesz onboarding z
gołym `config:recommended`, czyli bez całej tej polityki.

Potwierdzone dry-runem: na repo bez scalonego configu Renovate mówi wprost „Would
create onboarding PR".

> Uwaga eksportu: ten krok został już przez Ciebie wykonany — aplikacja Renovate
> jest zainstalowana i spięta.

### Świadomie: zero automerge w tej fazie

Automerge jest wyłączony we wszystkich pięciu presetach. Najpierw chcemy
zobaczyć, ile i jakich PR-ów bot generuje na żywo, a bramki otwierać dopiero tam,
gdzie CI cokolwiek realnie sprawdza. To jest treść Faz 3 i 4.

---

## Kolejność wdrożenia

| Faza | Zakres | Efekt | Ryzyko |
|---|---|---|---|
| 1 ✓ | upload-artifact v3→v4 w 3 repo, przywrócone `on:` w globalsQA-banking | 4 repo przestaje być trwale czerwone; PicsImprove świadomie pominięty | zrobione — 4 PR-y wystawione |
| 1b ✓ | Usunąć nadmiarowe wpisy z `overrides` — realny zakres 3 repo, nie 16 | odblokowuje npm ci w testBasketPw, code-reviewer i playwright-lum-project | zrobione — 3 PR-y, każdy zweryfikowany lokalnie |
| 2 ✓ | Repo sterujące z 5 presetami, klasyfikacja 102 repo, 3 piloty zasiane | polityka w jednym miejscu; zostaje ręczna instalacja GitHub App | zrobione — 4 PR-y; zachowanie zmierzone dry-runem |
| 3 | Minimalny workflow `verify` we wszystkich repo objętych automerge | zamyka dziurę skipped/neutral i daje realną bramkę | niskie |
| 4 | Automerge patch+minor na pilotach, obserwacja tygodnia | pierwsze naprawdę bezobsługowe merge | średnie — tu patrzymy uważnie |
| 5 | Sonda buildowalności 22 repo archiwalnych, potem decyzja per repo | wiemy, które z 2016–2019 da się w ogóle automatyzować | niskie — sonda jest read-only |
| 6 | Rozjazd na wszystkie 79 repo, drenaż 64 zaległych PR-ów | backlog znika sam w 1,5–2 dni | średnie |
| 7 | Agent gh-aw + Gemini na padające buildy | same-naprawiające się podbicia; PR agenta zawsze do przeglądu | wymaga hardeningu z sekcji AI |

**Dlaczego naprawy CI są fazą pierwszą, a nie ostatnią.** Wybrałeś naprawę
testów, i to jest właściwa kolejność: dopóki repo jest trwale czerwone, automerge
nigdy się nie odpali, więc cała reszta infrastruktury nie ma tam czego pilnować.
Tiery 1–4 to około godziny pracy i odblokowują sześć repo.

---

## Strategia providerów AI (dopisane 18.08.2026, poza canvasem)

Ta sekcja nie pochodzi z canvasu — jest doprecyzowaniem Fazy 7 po Twojej decyzji
o wyborze providerów. Implementacja leży w katalogu [`ai/`](../ai/README.md).

### Decyzja

**DeepSeek jest głównym punktem dostępu do AI.** Domyślnie **Flash**, przy
trudniejszym przypadku **Pro** — ten sam dostawca, ten sam klucz, mocniejszy
model. OpenRouter jest zapasem na wypadek awarii DeepSeeka. Gemini zostaje
opisane w konfiguracji, ale jest **wyłączone**: nie ma klucza Google, a płatny
tier został odrzucony. Włączenie Gemini to zmiana statusu jednego wpisu.

| Rola | Provider | Model | Status |
|---|---|---|---|
| domyślny | DeepSeek | `deepseek-v4-flash` | aktywny |
| eskalacja | DeepSeek | `deepseek-v4-pro` | aktywny |
| zapas | OpenRouter | `google/gemini-3.7-flash` | aktywny |
| przewidziany | Gemini | `gemini-3.6-flash` | wyłączony |
| przewidziany | Gemini | `gemini-3.1-pro-preview` | wyłączony |

*(Wcześniejsza wersja tej sekcji stawiała Gemini jako domyślne, a DeepSeeka jako
zapas. Zostało to odwrócone po decyzji o niewchodzeniu na płatny tier Gemini.
Zapis zostawiam widoczny, żeby było jasne, że to zmiana decyzji, a nie
przeoczenie.)*

**Dlaczego eskalacja została u tego samego dostawcy.** Sprawdziłem na żywo, że
`api.deepseek.com` wystawia dokładnie dwa modele — `deepseek-v4-flash` i
`deepseek-v4-pro` — i że Pro realnie odpowiada. Pro jest trzykrotnie droższy i ma
pięciokrotnie niższy limit współbieżności (500 wobec 2500), czyli to inny profil
obliczeniowy, a nie ta sama rzecz pod inną nazwą. Eskalacja ma zmieniać moc
modelu, a nie dostawcę: zmiana dostawcy zmienia naraz model, tokenizer i obsługę
myślenia, więc nie dałoby się powiedzieć, czemu wynik się poprawił. OpenRouter
odpowiada na inne pytanie — „co, gdy DeepSeek nie odpowiada" — i dlatego jest
zapasem, nie eskalacją.

### Dlaczego przełączanie jest tanie: jeden protokół u wszystkich

Kluczowe ustalenie tej sekcji: **DeepSeek, OpenRouter i Gemini wystawiają
endpointy zgodne z OpenAI**, więc przełączenie providera to zmiana trzech
wartości — base URL, nazwy sekretu i nazwy modelu — a nie zmiana kodu.

| Provider | Base URL zgodny z OpenAI |
|---|---|
| DeepSeek | `https://api.deepseek.com` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |

Sprawdzone empirycznie: ten sam skrypt `ai/scripts/ai-call.sh`, bez zmiany ani
jednej linii, dostał poprawną odpowiedź z obu modeli DeepSeeka i z OpenRoutera, a
przez OpenRouter także z modeli Gemini. Potwierdzone na żywo także zejście na
zapas: przy podstawionym nieprawidłowym kluczu DeepSeeka oba jego wpisy odpadły na
HTTP 401, a odpowiedź przyszła z OpenRoutera. Endpoint Gemini potwierdzony co do
hosta i ścieżki (odpowiada „Please pass a valid API key" na nieprawidłowym
kluczu), ale **nie potwierdzony wywołaniem**, bo w środowisku nie było klucza
Gemini.

Zastrzeżenie, którego nie należy wygładzać: warstwa zgodności Gemini z OpenAI
jest przez Google **oznaczona jako beta** i nie ma pełnej parzystości funkcji.
Google wprost zaleca native SDK, jeśli nie jesteś już zainwestowany w biblioteki
OpenAI. Do naszego zastosowania — jedno wywołanie chat/completions bez
strumieniowania — to wystarcza, ale nie należy na tej warstwie budować niczego
bardziej wymyślnego bez ponownego sprawdzenia.

### Koszty — korekta pozycji z tabeli kosztów

Tabela kosztów wyżej wymienia „Gemini API — triage i naprawy: 2–6 USD" i
„OpenRouter — eskalacje: 1–3 USD". Po przestawieniu łańcucha na DeepSeeka
**pierwsza pozycja wypada z rachunku** (Gemini jest wyłączone), a cała warstwa
schodzi wyraźnie niżej: domyślny model jest około siedmiokrotnie tańszy na wejściu
i ponad jedenastokrotnie na wyjściu od `gemini-3.6-flash`, który miał tę rolę
wcześniej.

| Model | Rola | Wejście / 1M | Wyjście / 1M |
|---|---|---|---|
| `deepseek-v4-flash` | domyślny | 0,22 USD poza szczytem / 0,44 w szczycie | 0,66 / 1,32 USD |
| `deepseek-v4-pro` | eskalacja | 0,66 / 1,32 USD | 1,98 / 3,96 USD |
| `google/gemini-3.7-flash` (OpenRouter) | zapas | 0,375 USD | 1,875 USD |
| `gemini-3.6-flash` | wyłączony | 1,50 USD | 7,50 USD |
| `gemini-3.1-pro-preview` | wyłączony | 2,00 USD (4,00 powyżej 200k) | 12,00 USD (18,00 powyżej 200k) |

Szczyt u DeepSeeka to 01:00–04:00 i 06:00–10:00 UTC. Trafienie w cache wejściowy
jest u niego skrajnie tanie (0,007–0,014 USD za milion dla Flasha), co dla agenta
czytającego wielokrotnie ten sam log builda ma realne znaczenie.

Dwie rzeczy, które podnoszą realny koszt względem tej tabeli:

- **Tokeny myślenia liczą się jako wyjście**, także u DeepSeeka — tryb myślenia
  jest domyślny dla obu wariantów V4. Zmierzone na żywo: jednosłowna odpowiedź
  kosztowała 42 tokeny myślenia u Flasha i 67 u Pro, a `gemini-3.7-flash` przez
  OpenRouter 124. Dla modeli Gemini 3 myślenia **nie da się wyłączyć**.
- **Skala się nie zmienia, ale zasada zostaje.** Przy tych cenach cały łańcuch to
  nadal jednostki dolarów miesięcznie, co nie jest argumentem za eskalowaniem w
  pętli. Jeden przebieg Flash, jeden Pro, potem człowiek.

Znika natomiast poprzedni argument o darmowym tierze: DeepSeek go nie ma, więc nie
istnieje pokusa użycia tieru, w którym dostawca wykorzystuje treść do ulepszania
produktów. Logi buildów z 44 prywatnych repo idą wyłącznie przez płatne API.

### Bezpieczeństwo: agent nigdy nie jest bramką

To jest doprecyzowanie trzeciej zasady z sekcji „AI: agent, wyłącznie gdy build
padnie", i najważniejsza rzecz w całej tej warstwie. Agent może **tylko**
zaproponować zmianę — wystawić PR albo oddać patch jako artefakt. Nie ma prawa
ocenić, czy PR przeszedł, scalić czegokolwiek, ani ustawić statusu checka, na
którym opiera się decyzja o merge.

Powód jest konkretny i został już w tym planie nazwany: głównym ryzykiem nie jest
złośliwy współpracownik, a zatruty changelog paczki, który agent przeczyta jako
instrukcję. Model, który daje się przekonać treścią wejścia, nie może decydować,
co wjeżdża na `main`.

Szablon workflow (`ai/templates/ai-fix-build.yml`) jest **wyłączony domyślnie** —
leży poza `.github/workflows/`, więc GitHub go nie widzi, i ma tylko trigger
`workflow_dispatch`. Uprawnienia: `contents: read` i `actions: read`, nic więcej.
Checkout z `persist-credentials: false`.

### Gdzie mieszkają klucze: jedno repo sterujące, nie sto

Sprawdzone, bo brzmiało jak założenie: **na koncie osobistym nie istnieją sekrety
Actions na poziomie użytkownika.** Dokumentacja GitHuba wymienia trzy poziomy —
organizacja, repozytorium, środowisko repozytorium — i tylko poziom organizacyjny
pozwala współdzielić jeden wpis między repozytoriami. Potwierdza to API: `GET
/user/actions/secrets` zwraca **404** (endpoint nie istnieje), podczas gdy `GET
/user/codespaces/secrets` zwraca **403** z dokumentacją tego endpointu, czyli
istnieje — ale to magazyn Codespaces, którego Actions nie czyta. Konto `dudziakm`
to `type=User` bez żadnej organizacji.

Wzorzec, który z tego wynika: **klucze AI leżą wyłącznie w `dep-automation`**, tam
mieszka workflow agenta, a do repozytoriów docelowych sięga on fine-grained
tokenem z uprawnieniami Contents: Read, Actions: Read i Metadata: Read — i niczym
więcej. Pełny opis, wraz z rotacją, zachowaniem przy wygasłym tokenie i wadami
tego układu (token przywiązany do człowieka, jeden punkt kompromitacji, limity
minut Actions dla repo prywatnych), jest w [`ai/README.md`](../ai/README.md) w
sekcji „Gdzie mieszkają sekrety na koncie osobistym".

### `gh-aw`: co potwierdzone, co obejściem

`github/gh-aw` ma wbudowane silniki `copilot`, `claude`, `codex`, `gemini` i
`pi`. **DeepSeeka na tej liście nie ma**, więc domyślny provider tej warstwy
wymaga w gh-aw trasy obejściowej: `engine: copilot` w trybie BYOK, przez
`COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY` i `COPILOT_MODEL`, czyli
znów te same trzy wartości. To znany koszt wyboru DeepSeeka, wart wypowiedzenia
wprost: gdyby Gemini było domyślne, wystarczyłoby `engine: gemini` plus sekret
`GEMINI_API_KEY` (albo bezkluczowe Google Workload Identity Federation, które
przełącza silnik na backend Vertex AI). Przy jednym wywołaniu
`chat/completions` różnica jest niewielka, ale przestaje być niewielka, gdyby
warstwa miała korzystać z wbudowanych mechanizmów silnika.

Zapis Fazy 7 w tabeli faz („Agent gh-aw + Gemini") należy więc czytać jako „agent
gh-aw + DeepSeek przez BYOK".

Mechanizmy bezpieczeństwa gh-aw, na które plan liczy: job agenta domyślnie
read-only w sandboksie, firewall ruchu wychodzącego z listą dozwolonych hostów,
oraz zapisy do GitHuba wyłącznie przez osobne, walidowane joby `safe-outputs`.
To zgadza się z tym, co plan założył w sekcji architektury. Nieuruchamiane —
mapowanie pochodzi z dokumentacji, nie z działającego workflow.

---

## Źródła kluczowych ustaleń

- Zachowanie automerge i nieobecność testów: [docs.renovatebot.com/key-concepts/automerge](https://docs.renovatebot.com/key-concepts/automerge/)
- `ignoreTests` i `platformAutomerge`: [configuration-options](https://docs.renovatebot.com/configuration-options/)
- Karencja wersji: [minimum-release-age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)
- Bug ze wiecznie pendującym stability check: [renovate#45236](https://github.com/renovatebot/renovate/issues/45236)
- Zakresy vs lockfile: [rangeStrategy](https://docs.renovatebot.com/configuration-options/#rangestrategy)
- Tryb cichy dla repo archiwalnych: [mode: silent](https://docs.renovatebot.com/self-hosted-configuration/#mode)
- Baza podatności użyta do audytu overrides: [osv.dev querybatch](https://google.github.io/osv.dev/post-v1-querybatch/)
- Karencja w npm wymaga npm ≥ 11.10.0: [npm config](https://docs.npmjs.com/cli/v12/using-npm/config/#min-release-age)
- Hardening pnpm: [pnpm.io/supply-chain-security](https://pnpm.io/supply-chain-security)
- Framework agentowy GitHuba: [github.github.com/gh-aw](https://github.github.com/gh-aw/)
- Kompromitacja Gemini CLI przez prompt injection: [pillar.security](https://www.pillar.security/blog/my-agentic-trust-issues-from-prompt-injection-to-supply-chain-compromise-on-gemini-cli)

Źródła dopisane do sekcji o providerach AI:

- Modele i cennik DeepSeeka, w tym base URL zgodny z OpenAI oraz limity współbieżności: [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- Cennik OpenRoutera pobrany maszynowo: [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models)
- Cennik Gemini Developer API: [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing)
- Zgodność Gemini z OpenAI (endpoint, ograniczenia, `reasoning_effort`): [ai.google.dev/gemini-api/docs/openai](https://ai.google.dev/gemini-api/docs/openai)
- Limity Gemini API i progi tierów: [ai.google.dev/gemini-api/docs/rate-limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- Silniki gh-aw i ich uwierzytelnianie: [github.github.com/gh-aw/reference/engines](https://github.github.com/gh-aw/reference/engines/), [reference/auth](https://github.github.com/gh-aw/reference/auth/)
- Gemini w gh-aw: [github.github.com/gh-aw/engines/gemini](https://github.github.com/gh-aw/engines/gemini/)

Źródła dopisane do sekcji o sekretach:

- Poziomy sekretów Actions (organizacja, repozytorium, środowisko): [docs.github.com/actions/concepts/security/secrets](https://docs.github.com/en/actions/concepts/security/secrets)
- Typy sekretów i zasięg współdzielenia: [docs.github.com/code-security/reference/secret-security/secret-types](https://docs.github.com/en/code-security/reference/secret-security/secret-types)
- Ograniczenia i limity fine-grained PAT (brak Checks API, limit 50 tokenów, ważność do 366 dni): [docs.github.com/authentication/.../managing-your-personal-access-tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens-limitations)
- Minuty Actions w limicie planu: [docs.github.com/billing/reference/product-usage-included](https://docs.github.com/en/billing/reference/product-usage-included)

### Metodologia i znane braki

Dane o repozytoriach zebrane 18.08.2026 przez GitHub REST i GraphQL API na koncie
dudziakm. Dry-run Renovate 44.33.2 wykonany lokalnie w trybie tylko do odczytu.
Logi 14 padających workflowów przeanalizowane read-only; dla czterech runów z
maja 2026 i grudnia 2025 logi wygasły i przyczyna jest oznaczona jako
wnioskowana.

Audyt overrides przebiegł w trzech krokach, bo pierwszy dał mylący wynik.
Najpierw 86 dokładnych pinów z 16 repo poszło wsadowo do OSV — sześć wróciło jako
podatne. Potem sprawdzenie lockfile'i pokazało, że pięć z tych pakietów nie
występuje w drzewie zależności, więc piny są bezczynne; szósty (`nanoid`) nie
obowiązuje, a zainstalowana wersja jest już załatana. Dopiero trzeci krok — próba
przeliczenia lockfile'a na klonach `testBasketPw` i `code-reviewer` — ujawnił
prawdziwą usterkę (`EUSAGE` plus `EOVERRIDE`) i pozwolił sprawdzić lekarstwo
end-to-end. Wnioski z kroku pierwszego zostały w planie skorygowane, nie
usunięte, żeby widać było, dlaczego prosty odczyt `package.json` tu nie
wystarcza. Znany brak: 18 wpisów zapisanych jako zakresy (`^`) pominięto, bo bez
rozwiązania drzewa nie da się ich jednoznacznie sprawdzić.

Krok czwarty, dodany po tym, jak rozwijanie lekarstwa na 12 repo dało cztery
„porażki", z których żadna nie była porażką lekarstwa. Dla każdego repo: czysty
HEAD, odłożony `node_modules`, `npm ci --dry-run --ignore-scripts`. Pierwszy
przebieg tego pomiaru był zafałszowany obecnością `node_modules` z moich
wcześniejszych instalacji i pokazywał „up to date"; wynik w planie pochodzi z
przebiegu po odłożeniu tego katalogu. Ustalone: siedem repo instaluje się
poprawnie mimo rozjazdu, jedno poddaje się lekarstwu, trzy mają konflikty
peer-dependency (inna klasa usterki), jedno nie ma lockfile'a. Osobno odrzucona
hipoteza dla `3rd-devs-my`: `npm ci` padał tam na kompilacji natywnego `canvas`
2.11.2 pod node 24 / darwin arm64, czyli na moim sprzęcie, a nie w repo — pod
`--ignore-scripts` instaluje 1516 paczek i build przechodzi.
