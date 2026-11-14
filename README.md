# WoW-Forever-Addons

Addons für WoW Forever (Interface 16001).

## Preisanker

Findet im Auktionshaus Auktionen unter dem Händlerpreis (kaufen, beim NPC-Händler verkaufen)
und Händlerware, die im Auktionshaus teurer ist als beim Händler.
Einbau und Bedienung: [Preisanker/LIESMICH.txt](Preisanker/LIESMICH.txt).

Stand 14.11.2026: nur gegen eine nachgebaute Spiel-API getestet, noch nicht im echten Spiel gelaufen.

## Händlerprofit

Zeigt herstellbare Gegenstände, die sich mit Gewinn beim Händler verkaufen lassen.
Materialpreise kommen aus Auctionator (optional). Fenster öffnen mit `/hp`.
Einbau: den Ordner `Haendlerprofit` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren.

## Test

```
lua5.1 tests/test.lua
```

`tests/spiel.lua` bildet die benutzte Spiel-API nach (Auktionshaus mit Drossel, Händler, Taschen).
