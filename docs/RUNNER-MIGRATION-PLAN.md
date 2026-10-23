# Migracja verify z Maca na własny runner (Windows/Ubuntu)

## Cel

Zastąpić `Michals-Mac-dependency-automation` jako bramkę verify, bo:
- Mac jest single point of failure (śpi, pada, zapełnia się dysk).
- GH-hosted `ubuntu-latest` ma limit minut, które szybko się zużywają.
- Własny runner (stary PC z Windows lub Ubuntu) daje niezależność i 0 kosztów minut.

## Wymagania wstępne

| Komponent | Minimum | Uwagi |
|---|---|---|
| CPU | 2 rdzenie | Node buildy są single-threaded w większości |
| RAM | 8 GB | 4 GB to absolutne minimum, 8 GB komfortowo |
| Dysk | 20 GB wolne | npm cache + node_modules potrafią urosnąć |
| System | Ubuntu 22.04 LTS **lub** Windows 10/11 + WSL2 | Ubuntu prostsze w utrzymaniu |
| Sieć | Dowolna, ale stabilna | npm ci pobiera dużo |

## Krok 1: Przygotowanie maszyny

### Ubuntu (zalecane)

```bash
# 1. Zainstaluj Node.js (LTS 22)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. Zainstaluj pnpm, yarn, corepack
sudo corepack enable
sudo npm install -g pnpm yarn

# 3. Zainstaluj GitHub Actions runner
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.320.0.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz

# 4. Skonfiguruj runner
./config.sh --url https://github.com/dudziakm/dep-automation \
  --token <TOKEN_Z_GITHUB> \
  --name "linux-verify-runner" \
  --labels "self-hosted,Linux,X64,dependency-automation" \
  --work _work \
  --unattended

# 5. Uruchom jako usługę
sudo ./svc.sh install
sudo ./svc.sh start
```

### Windows + WSL2

```powershell
# W PowerShell (admin)
wsl --install Ubuntu-22.04
# Po restarcie, w Ubuntu:
# dalej jak w sekcji Ubuntu powyżej
```

## Krok 2: Rejestracja runnera na GitHub

1. Wejdź na https://github.com/dudziakm/dep-automation/settings/actions/runners/new
2. Wybierz Linux x64
3. Skopiuj token i użyj w `./config.sh --token`
4. Nadaj etykiety: `self-hosted,Linux,X64,dependency-automation`

## Krok 3: Zmiana workflow

W `.github/workflows/verify-dependency-prs.yml` zmień:

```yaml
# Z:
runs-on: [self-hosted, macOS, ARM64]

# Na:
runs-on: [self-hosted, Linux, X64]
```

Lub zrób to warunkowo (fallback na Maca):

```yaml
runs-on: ${{ matrix.runner || 'self-hosted,macOS,ARM64' }}
```

I dodaj w macierzy:

```yaml
matrix:
  runner: [self-hosted, Linux, X64]
```

## Krok 4: Sekrety

Na nowym runnerze potrzebne są te same sekrety:
- `RENOVATE_TOKEN` — do checkoutu PR-ów
- `VERIFY_TOKEN` — do publikowania statusu verify

Sekrety są na poziomie repo, więc runner je odziedziczy.

## Krok 5: Test

```bash
# Z Maca lub z nowego runnera
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
export GH_TOKEN="$(gh auth token --user dudziakm)"
gh workflow run verify-dependency-prs.yml --repo dudziakm/dep-automation \
  -f repository=web-ideas -f pr_number=177
```

## Krok 6: Wyłączenie Maca

Gdy nowy runner działa stabilnie przez tydzień:
1. Usuń etykietę `dependency-automation` z Maca
2. Zatrzymaj usługę runnera na Macu: `sudo ./svc.sh stop`
3. Opuść Maca z grupy runnerów

## Utrzymanie

| Zadanie | Częstotliwość | Komenda |
|---|---|---|
| Czyszczenie npm cache | gdy < 15 GB wolne | `npm cache clean --force` |
| Aktualizacja runnera | co miesiąc | `cd ~/actions-runner && ./bin/Runner.Listener configure --url ... --token ...` |
| Restart usługi | po aktualizacji | `sudo ./svc.sh restart` |

## Ryzyka i mitigacje

| Ryzyko | Prawdopodobieństwo | Mitigacja |
|---|---|---|
| Stary PC pada częściej niż Mac | średnie | Monitoruj `gh api repos/dudziakm/dep-automation/actions/runners`; miej Maca jako fallback |
| WSL2 na Windows jest niestabilny | niskie | Użyj natywnego Ubuntu zamiast WSL2 |
| Brak miejsca na dysku | średnie | Cron: `npm cache clean --force` co tydzień |
| Node/npm wersje dryfują | niskie | Pin w `verify-target.sh` (już zrobione) |
