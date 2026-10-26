# Lista 02 - odpowiedzi na pytania projektowe

Odpowiedzi odnoszą się do kontraktów w `contracts/list-02/` i wykonanych
testów w `test/list-02/`. Dane gazowe pochodzą z
[`gas-measurements.json`](./gas-measurements.json), z pomiaru 26.10.2026.

## 1. Wpływ ścieżki routingu: V1 przez ETH a bezpośrednie V2

V1 wymaga **dwóch osobnych pul**: A/ETH oraz B/ETH. W `swapV1ToV1`
router pobiera A od użytkownika, zatwierdza transfer do pierwszej puli,
zamienia A na ETH, następnie wpłaca otrzymane ETH do drugiej puli i wysyła
B odbiorcy. Są dwa obliczenia ceny, dwie opłaty 0,3%, dwa zapisy rezerw
oraz dwa przejścia z wartością ETH. Ten konkretny router wykonuje trzy
transfery ERC20: użytkownik→router, router→pula A, pula B→odbiorca.

`swapV2` pobiera A bezpośrednio do pary A/B i wywołuje jeden `swap`.
Występują dwa transfery ERC20: użytkownik→para oraz para→odbiorca,
jeden końcowy zapis rezerw i jedno sprawdzenie k z opłatą.
W obu wariantach routera cała wymiana jest jedną transakcją.

Zmierzony `transactionReceipt.gasUsed`:

| Wariant początkowy | V1 atomowo przez router | V1 jako suma 2 osobnych transakcji | V2 przez router |
| --- | ---: | ---: | ---: |
| Każda pula V1: 100 tokenów/100 ETH; V2: 100 A/100 B; odbiorca ma 0 B | 158 334 | 138 574 | 103 475 |
| Te same rezerwy; odbiorca ma już 1 wei B | 144 654 | 121 474 | 86 375 |
| Te same pule V1; V2: 50 A/50 B; odbiorca ma 0 B | 158 334 | 138 574 | 103 475 |

Wejście to zawsze 1 A, tokeny mają 18 miejsc dziesiętnych. W pierwszym
wierszu różnica atomowych ścieżek wynosi **54 859 gas**. Dwa samodzielne
swapy V1 kosztowały 66 146 + 72 428 = **138 574 gas**. Pomijają narzut
routera V1 i dodatkowy transfer A, ale płacą koszt podstawowy dwóch
transakcji i nie dają wspólnego revertu obu etapów.

Wyniki zależą od implementacji. Nie można z nich wyprowadzić uniwersalnej
relacji kosztów historycznych protokołów Uniswap. Tutaj używane są te same
mocki ERC20, istniejące allowance użytkownika, ten sam kompilator
0.8.37, optimizer 200 i Cancun. Pomiar obejmuje gaz podstawowy transakcji,
calldata, wykonanie i zwroty gazu; nie obejmuje wdrożeń, mintowania,
zasilania pul ani wcześniejszych zatwierdzeń użytkownika. Zawiera
`forceApprove` wykonywane **wewnątrz** atomowego routera V1.
Każda alternatywa zaczyna się z przywróconego snapshotu; ciepłe odczyty
nie przenoszą się między osobnymi transakcjami. To pomiar gazu EVM,
nie czasu wykonania komputera ani kosztu w PLN/ETH.

Drugie porównanie pokazuje wpływ zapisu salda odbiorcy z zera lub z wartości
niezerowej. Różnica V1 routera maleje o 13 680 gas, a V2 o 17 100 gas;
odmienne zwroty i ich limit wpływają na ostateczny koszt rachunku.
Dlatego nie należy porównywać wariantów z różnymi stanami odbiorcy.

Jest też różnica ekonomiczna: przy rezerwach 100/100 na każdej puli
V1 daje **0,974604535974342600 B**, a V2 100/100 daje
**0,987158034397061298 B**. To łączny wpływ drugiej prowizji i głębokości
trasy. Równe rezerwy poszczególnych pul nie oznaczają równej efektywnej
głębokości. Bez opłat złożenie dwóch symetrycznych pul 100/100 daje
funkcję `100 × input / (100 + 2 × input)`, taką jak bezpośrednia para
50/50. Dlatego trzeci wariant dopasowuje tę głębokość. V2 daje w nim
**0,977508480891032805 B**, a V1 pozostaje przy poprzednim wyniku.
V1 dodatkowo wymaga rezerw ETH w obu pulach; kapitał nie jest identyczny.

## 2. Dlaczego korekta prowizji dotyczy sald i rzeczywistego wejścia?

Prowizję nalicza się od **nowej wpłaty**, a nie od kapitału, który już
znajduje się w puli. Przy optymistycznym transferze kontrakt dopiero
po callbacku wie, ile rzeczywiście otrzymał i w którym tokenie.
Dlatego najpierw odtwarza wejścia z rzeczywistych sald:

```text
input = max(balanceAfter - (reserveBefore - output), 0)
```

Sprawdzenie w `MiniUniswapV2.swap` to:

```text
(balance0 × 1000 - input0 × 3)
× (balance1 × 1000 - input1 × 3)
>= reserve0 × reserve1 × 1000²
```

Nie mnożymy całego końcowego salda przez 997/1000. Dla standardowego
tokenu saldo można rozpisać jako `reserve - output + input`, zatem:

```text
balance × 1000 - input × 3
= (reserve - output) × 1000 + input × 997
```

Tylko 99,7% wejścia finansuje wyjście w równaniu ceny. Fizycznie w puli
pozostaje 100% wejścia: różnica jest wynagrodzeniem LP. Mnożenie samych
początkowych rezerw przez 997 opodatkowałoby też stare środki albo
obniżało wymaganą prawą stronę niezależnie od faktycznej wpłaty, przez co
nie egzekwowałoby właściwej prowizji. Korekta obu wejść obsługuje także
spłatę oboma tokenami. Równość z końcowego warunku daje używany
w kwotowaniu wzór `amountIn × 997 × reserveOut / (reserveIn × 1000 + amountIn × 997)`.

Testy porównują wynik z niezależnie zapisanym wzorem, sprawdzają wzrost
zwykłego k i nierówność po korekcie opłat. Wyjście zawyżone o 1 wei oraz
kwotowanie bez opłaty kończą się `InvariantK`. Układ równania odpowiada
[sprawdzeniu w oryginalnym UniswapV2Pair](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol).

## 3. Co zabezpiecza optymistyczną wypłatę przed kradzieżą?

W naszym V2 połączono następujące mechanizmy:

1. Wyjście musi być niezerowe i ściśle mniejsze od odpowiednich rezerw;
   odbiorcą nie może być zero, sama pula ani adres któregoś tokenu.
2. `nonReentrant` blokuje ponowny swap, wpłatę/wyjście płynności i `sync()`
   podczas transferu lub callbacku. Nie da się podmienić rezerw między
   wypłatą a weryfikacją.
3. `SafeERC20` odrzuca nieudane transfery. Końcowe wejścia wynikają
   z faktycznych sald, a nie z deklaracji odbiorcy. Co najmniej jedno
   wejście musi być dodatnie.
4. Kontrola k z korektą 0,3% musi przejść. Limit `uint112` jest sprawdzany
   przed mnożeniem, aby rachunek nie zawinął się ani nie obciął rezerw.
5. Dopiero po kontroli następuje zapis rezerw i zdarzenie `Swap`.

Jeżeli callback nie spłaci, spłaci za mało, spróbuje nieobsłużonego
ponownego wejścia lub sam zrobi revert, EVM cofa **całe drzewo wywołań**.
Odbiorca traci otrzymane chwilowo tokeny, a zmiany jego stanu też znikają.
Jeśli router wcześniej w tej transakcji pobrał token wejściowy, ten
transfer również jest cofnięty. Testy sprawdzają te salda i zmiany stanu,
nie tylko sam fakt wystąpienia błędu.

Złapanie błędu reentrancy przez callback nie omija k: taki callback może
kontynuować tylko wtedy, gdy na końcu normalnie spłaci pełną należność.
Pokazuje to `test_CaughtReentrancyStillRequiresFullRepayment`.
Atomowość nie cofa opłaty za gaz nieudanej transakcji ani operacji
wykonanej wcześniej w **osobnej** transakcji.

To zabezpieczenie zakłada standardowe zachowanie wybranych ERC20.
Nie chroni przed tokenem, który arbitralnie kłamie w `balanceOf` lub
zmienia cudze salda; te tokeny są poza świadomie przyjętym zakresem.

## 4. Arbitraż przez callback bez początkowych tokenów

`FlashArbitrage` ma saldo 0 A i 0 B. W teście źródłowa para ma
100 A / 100 B, a druga para 100 A / 200 B:

1. Kontrakt wywołuje `source.swap(10 A, 0, address(this), data)`.
2. Dostaje 10 A i wchodzi do callbacku. Sprzedaje A na drugiej parze,
   otrzymując około 18,1322 B, zgodnie z wzorem 997/1000.
3. Spłaca pierwszą parę tokenem B. Dla dokładnego wyjścia 10 A
   funkcja `getAmountIn` daje konserwatywnie zaokrągloną należność:
   `floor(100 B × 10 A × 1000 / (90 A × 997)) + 1 wei`, około 11,1445 B.
4. Różnicę, około 6,9877 B, wysyła właścicielowi. Źródłowa para
   po powrocie z callbacku sprawdza własne k i kończy transakcję.

Test `test_ArbitrageStartsWithZeroTokensAndPaysProfit` wylicza i sprawdza
dokładną różnicę w wei. Powyższe liczby są wynikiem arytmetyki tego
scenariusza, a nie obserwacją cen z zewnętrznej giełdy. Brak kapitału
początkowego dotyczy **tokenów operacji**; inicjator transakcji nadal
potrzebuje ETH na gaz. W sieci testowej dostarcza je Hardhat.

Gdy spłacamy w **tym samym** pożyczonym tokenie, należność jest inna:
`ceil(borrowed × 1000 / 997)`. Efektywna opłata względem pożyczonej kwoty
wynosi około 0,3009027%, ponieważ 0,3% nalicza się od kwoty oddanej.
Spłata `borrowed × 1,003` może być za mała. Testy obejmują dokładne
zaokrąglenie oraz niedopłatę o jeden wei. Ten podział spłat opisuje też
[dokumentacja flash swapów Uniswap](https://developers.uniswap.org/docs/protocols/v2/guides/flash-swaps).

Przykład odbiorcy zabezpiecza callback przez sprawdzenie `msg.sender`
równego zapisanej parze, `sender == address(this)` i aktywnego własnego
zlecenia. Samo posiadanie poprawnej sygnatury callbacku nie dowodzi
autentyczności pożyczki. Wywołanie przez obcego może inaczej wykorzystać
prefunding lub allowance odbiorcy. Test odrzuca również callback
z podszytym adresem pary, gdy nie ma aktywnej operacji.

Drugim warunkiem brzegowym jest zmiana opłacalności: `execute` ma deadline
i `minProfit`, a callback przed operacją na drugiej parze sprawdza, czy
**przychód tej wymiany** pokrywa spłatę i wymagany zysk. Wcześniej wpłacone
tokeny nie maskują straty. Brak zysku powoduje revert obu rynków.
Próg zysku w B nie uwzględnia kosztu gazu płaconego w ETH; o ekonomicznej
opłacalności całej transakcji trzeba decydować także z uwzględnieniem tego kosztu.
