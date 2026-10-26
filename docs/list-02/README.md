# Lista 02 — Mini Uniswap v1 i v2

Implementacja zadania projektowego w istniejącym `evm-lab`. Wykonania są
automatycznymi testami: przygotowują konta i płynność, wysyłają transakcje,
sprawdzają salda, udziały LP, zdarzenia i odrzucanie ataków. Lista 01 pozostaje
częścią wspólnego zestawu testów.

## Uruchomienie lokalne

Z katalogu głównego repozytorium:

```bash
bun install --frozen-lockfile
bun run check
```

Do odtworzenia środowiska pomiarowego: **Bun 1.4.4, Node.js 24.21.0,
Hardhat 3.18.1, viem 2.57.3, OpenZeppelin 5.6.1, forge-std 1.16.2,
Solidity 0.8.37+commit.f401782d**. Wersje zależności rozstrzyga istniejący
`bun.lock`; nie trzeba dodawać nowych pakietów. Bun instaluje zależności
i uruchamia skrypty, a CLI Hardhata i testy TypeScript działają na Node.js.

Pierwsza instalacja wymaga internetu, Git (zależność `forge-std`) i pobrania
kompilatora przez Hardhat. Potem testy działają bez zewnętrznego RPC,
podpinania portfela, prawdziwych środków i pliku `.env`.
`hardhatMainnet` jest tutaj nazwą **symulowanej sieci lokalnej**.

`bun run check` wykonuje kompilację, sprawdzanie typów i wszystkie testy.
Używaj skryptów `bun run …`; sam `bun test` uruchamia inny runner.

```bash
# Wyłącznie lista 02: Solidity + test integracyjny z pomiarem gazu
bun run test:list-02

# Tylko pomiar gazu, bez zmieniania zapisanego raportu
bun run test:list-02:gas

# Ponowny pomiar i zapis docs/list-02/gas-measurements.json
bun run report:list-02:gas

# Poszczególne grupy, np. flash swapy
bunx hardhat test solidity test/list-02/FlashSwap.t.sol

# Pełny projekt z profilem production
bun run test:production
```

Oba istniejące profile kompilacji zachowują Solidity 0.8.37 i optymalizator
200 runs. Przypięto `evmVersion: cancun`, a dla `hardhatMainnet` również
`hardfork: cancun`, aby domyślne zmiany wersji EVM nie przesuwały benchmarku.
Fuzzing ma 256 prób na funkcję i stały seed `0x02`. Testy Solidity wykonuje
Hardhat; nie wymagają zainstalowanych programów `forge` ani `anvil`.

## Pliki

| Ścieżka | Zawartość |
| --- | --- |
| `contracts/list-02/MiniUniswapV1.sol` | Pula ERC20/ETH, płynność, udziały LP, dwa kierunki swapu |
| `contracts/list-02/MiniUniswapV2.sol` | Para ERC20/ERC20, optymistyczny transfer, callback i weryfikacja k |
| `contracts/list-02/PoolShares.sol` | LP jako ERC20, terminy, błędy, minimum płynności, ReentrancyGuard |
| `contracts/list-02/PoolMath.sol` | Kwotowanie `getAmountOut` / `getAmountIn`, opłata 997/1000, limit rezerw |
| `contracts/list-02/IMiniV2Callee.sol` | Interfejs callbacku flash swapu |
| `contracts/list-02/MiniRouter.sol` | Atomowe ERC20→ETH→ERC20 przez dwie pule V1 i bezpośrednie V2 |
| `contracts/list-02/examples/FlashArbitrage.sol` | Wykonywalny przykład arbitrażu bez tokenów początkowych |
| `contracts/list-02/mocks/TestTokens.sol` | Tokeny testowe, w tym brak wartości zwrotnej i zachowania złośliwe |
| `test/list-02/` | Testy Solidity, fuzzing i benchmark TypeScript |
| `test/fixtures/list-02/` | Izolowana lokalna sieć i wspólny stan początkowy benchmarku |
| [ODPOWIEDZI.md](./ODPOWIEDZI.md) | Odpowiedzi na cztery pytania zadania |
| [gas-measurements.json](./gas-measurements.json) | Surowe wyniki, środowisko, hashe transakcji i sumy SHA-256 źródeł benchmarku |
| [test-results.txt](./test-results.txt) | Zapis końcowego `bun run check` |

## MiniUniswapV1

Konstruktor dostaje adres istniejącego ERC20. Pula ma jeden token i natywny
ETH. Kwoty są w najmniejszych jednostkach; tokeny demonstracyjne mają 18 miejsc
dziesiętnych. Wzór wymiany:

```text
amountOut = floor(amountIn × 997 × reserveOut
                  / (reserveIn × 1000 + amountIn × 997))
```

- `addLiquidity(maxTokens, minShares, deadline)` jest `payable`. Pierwszy
  dostawca ustala proporcję. Kolejni wpłacają całe przesłane ETH; kontrakt
  pobiera tylko odpowiadającą mu ilość tokenów, zaokrągloną w górę. Kwota
  tokenów nie może przekroczyć `maxTokens`, a liczba LP musi spełniać `minShares`.
- `removeLiquidity(shares, minTokens, minEth, to, deadline)` spala LP
  wywołującego i wypłaca oba aktywa proporcjonalnie do całkowitej emisji LP.
- `ethToTokenSwap(minOut, to, deadline)` jest `payable`.
- `tokenToEthSwap(amountIn, minOut, to, deadline)` pobiera ERC20 przez allowance.
- `getReserves()` zwraca zapisany snapshot `(reserveToken, reserveEth)`.
  `sync()` włącza do niego bezpośrednie darowizny ERC20 lub wymuszone ETH.

Operacje V1 liczą proporcje i cenę z rzeczywistych sald na początku wywołania;
`msg.value` jest odejmowane od salda ETH przed kwotowaniem. Dzięki temu nowa
wpłata nie jest błędnie uznawana za poprzednią rezerwę. Darowizny zwiększają
wartość dla dotychczasowych LP; nie dają darczyńcy nowych udziałów.

## MiniUniswapV2

Konstruktor dostaje dwa różne adresy ERC20. Kolejność argumentów określa
`token0` i `token1`; adresy nie są sortowane.

- `addLiquidity(desired0, desired1, min0, min1, minShares, deadline)` dobiera
  optymalną proporcję i pobiera tylko użyte ilości tokenów. Dla kolejnych wpłat
  udziały to minimum udziałów wynikających z obu wpłacanych kwot. Punktem
  odniesienia są rzeczywiste salda przed wpłatą, także przy darowiznach.
- `removeLiquidity(shares, min0, min1, to, deadline)` spala LP wywołującego
  i wypłaca proporcjonalną część rzeczywistych sald.
- `swap(amount0Out, amount1Out, to, data)` najpierw wysyła zadane wyjścia.
  Niepuste `data` uruchamia na `to`:
  `miniUniswapV2Call(sender, amount0Out, amount1Out, data)`.
- Dopiero po callbacku kontrakt odczytuje salda i wylicza wejścia:

```text
amount0In = max(balance0 - (reserve0 - amount0Out), 0)
amount1In = max(balance1 - (reserve1 - amount1Out), 0)
adjusted0 = balance0 × 1000 - amount0In × 3
adjusted1 = balance1 × 1000 - amount1In × 3
require(adjusted0 × adjusted1 >= reserve0 × reserve1 × 1000²)
```

Core `swap` określa dokładne wyjście; nie ma osobnego parametru `minOut`
ani deadline. Dla normalnej wymiany używaj
`MiniRouter.swapV2(pair, zeroForOne, amountIn, minOut, to, deadline)`, który
weryfikuje te limity i pobiera wejście **w tej samej transakcji**.
`zeroForOne = true` oznacza token0→token1.

Nie wysyłaj ERC20 do pary osobną transakcją jako „zaliczki na swap”. Taki
transfer nie jest przypisany do nadawcy: ktokolwiek może wykorzystać nadwyżkę
lub wywołać `sync()`. Test `test_UnsyncedTransferIsPublicInputNotAnEscrow`
pokazuje to zachowanie. Router zapewnia atomowe pobranie i swap.

## LP, transfery i zabezpieczenia

W obu pulach pierwsza emisja to `floor(sqrt(amountA × amountB))`; z niej
**1000 najmniejszych jednostek LP** pozostaje na adresie samej puli.
Kontrakty nie mają funkcji pozwalającej przenieść lub spalić własne LP.
Reszta trafia do dostawcy. Kolejne emisje i wypłaty są zaokrąglane w dół;
zaokrąglenia nie mogą tworzyć wartości dla wycofującego. LP można przesyłać
jak zwykłe ERC20. Opłaty pozostają w saldach puli i zwiększają wartość LP.

Transfery ERC20 używają OpenZeppelin `SafeERC20`: `false` powoduje revert,
a poprawnie wykonany transfer bez wartości zwrotnej jest obsługiwany.
Wpłaty płynności i wejścia V1 dodatkowo sprawdzają dokładny przyrost salda.
Wszystkie funkcje zmieniające rezerwy, także `sync()`, mają wspólną blokadę
`nonReentrant`. Rezerwy są ograniczone do `uint112`; w V2 limit jest
sprawdzany przed mnożeniem skorygowanych sald.

Przy usuwaniu płynności LP są spalane przed zewnętrznymi transferami.
Zapis końcowych rezerw następuje po interakcjach, pod blokadą, na podstawie
rzeczywistych sald. Flash swap świadomie wymaga interakcji przed weryfikacją:
zastępuje klasyczne CEI kombinacją blokady, końcowego sprawdzenia wejść i k
oraz atomowości EVM. Błąd cofa transfery, emisję/spalenie LP, allowance,
zdarzenia i zmiany stanu callbacku. Odrzucenie płatności ETH przez odbiorcę
również cofa całą operację.

## Świadome uproszczenia

- Osobne, ręcznie tworzone pule: brak factory, CREATE2 i rejestru zaufanych par.
  Router przyjmuje adresy wybrane przez wywołującego; przykład zakłada użycie
  wdrożonych tutaj pul oraz zaufanych, zwykłych ERC20.
- V1 ma geometryczną pierwszą emisję LP i minimum płynności, podobnie jak
  ten V2; historyczny Uniswap V1 liczył pierwszą emisję z wpłaconego ETH.
  To model dydaktyczny AMM, a nie zgodność ABI z oryginalnym protokołem.
- Płynność jest obsługiwana bezpośrednio przez pulę przez `transferFrom`,
  zamiast oryginalnych niskopoziomowych operacji V2 `mint/burn` po przelewie.
  Zablokowane LP są na adresie puli, ponieważ ERC20 OpenZeppelin nie emituje na zero.
- Całe 0,3% trafia do LP. Brak opłaty protokołu, `feeTo`, TWAP,
  kumulatywnych cen, `permit`, `skim`, ścieżek wieloparowych V2 i upgrade'ów.
- Brak wsparcia dla rebasingu i tokenów z podatkiem od transferu. Kontrole
  wejścia wykrywają typowe takie wpłaty; nie stanowią walidatora dowolnie
  złośliwego ERC20. `minOut` zakłada zwykły transfer bez podatku na wyjściu.
  Tokeny testowe z publicznym `mint/burn` służą wyłącznie scenariuszom laboratoryjnym.
- `sync()` jest publiczne i aktualizuje snapshot do sald; k jest gwarancją
  **swapów**, nie niezmiennikiem usuwania/dodawania płynności ani `sync()`.
  Snapshot odczytany podczas callbacku jest stanem sprzed swapu i nie jest
  bezpiecznym oracle ceny. Kwoty ponad `uint112` są odrzucane, także jeśli
  wynikają z ogromnej darowizny; nie ma administracyjnego ratowania tokenów.
- `FlashArbitrage` obsługuje jeden kierunek, dwie pary o tej samej kolejności
  tokenów i zysk dla właściciela. Minimum zysku liczy w tokenie B;
  nie przelicza kosztu gazu na B. Przykład nie stanowi audytu produkcyjnego.

## Zakres i wyniki testów

| Zestaw | Sprawdzane zachowanie |
| --- | --- |
| `MiniUniswapV1.t.sol` | Pierwsza/kolejna płynność, proporcje, LP i zaokrąglenia, wyjście, oba swapy, fee/k, minOut/minLP/minAmounts, deadline, brak salda/allowance/LP, odbiorca ETH odrzucający przelew, tokeny false/no-return/tax, hook i reentrancy, darowizny, limit rezerw |
| `MiniUniswapV2.t.sol` | LP, obie gałęzie proporcji, dwa kierunki i zdarzenia amountIn, fee/k, zawyżenie wyjścia o wei, zerowe/wyczerpane rezerwy, atomiczny prepay/revert, terminy/limity routera, transfery obu tokenów, ataki przez hook, darowizny i sync |
| `FlashSwap.t.sol` | Transfer przed callbackiem, spłata tym samym/drugim tokenem i obu wyjść, brak spłaty/fee, niedopłata o wei, callback revert, cztery próby reentrancy, złapany błąd reentrancy, overflow w callbacku, arbitraż z saldem zero, strata/minProfit/deadline i fałszywy callback |
| `Routing.t.sol` | Dwie odrębne pule V1, atomiczne cofnięcie obu etapów, minETH/minOut, deadline, allowance i brak resztek na routerze, odwrotny kierunek V2 |
| `PoolMath.t.sol` | Wartości referencyjne 997/1000, zaokrąglenia, odwrotne kwotowanie i granice arytmetyki |
| `routing-gas.test.ts` | Rzeczywiste rachunki 12 transakcji w 3 wariantach, wyniki swapów, izolacja stanów i liczba transferów ERC20 |

Sprawdzenie 26.10.2026: **82 passing (74 Solidity, 8 nodejs)**,
w tym 7 istniejących testów listy 01 i 75 testów listy 02.
Siedem funkcji fuzz wykonuje po 256 prób; jedna sprawdza po 24 mieszane
operacje na próbę. Przeszły również kompilacja i sprawdzenie typów.

Szczegóły pomiarów i cztery odpowiedzi: [ODPOWIEDZI.md](./ODPOWIEDZI.md).
Tabela pomiarowa jest zapisem konkretnego wykonania, nie stałą gwarancją
kosztu; kolejne wyniki zapisuje się jawnie skryptem `report:list-02:gas`.
