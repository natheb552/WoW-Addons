# WoW-Forever-Addons

Addons für WoW Forever (Interface 16001).

## Händlerprofit

Gewinn mit festen Händlerpreisen, ein Fenster (`/hp`) mit drei Reitern:

- **Herstellen:** Rezepte, deren Ergebnis der Händler teurer abnimmt, als die Materialien kosten.
  Auktionspreise kommen wahlweise aus Auctionator (optional) oder aus dem eigenen Scan.
- **Unter Händlerpreis:** Auktionen unter dem Händlerpreis (kaufen, beim NPC-Händler verkaufen).
- **Händlerware:** Ware, die im Auktionshaus teurer ist als beim Händler.

Die beiden letzten Reiter und der eigene Scan sind das frühere Addon Preisanker; sein Code liegt in
`Haendlerprofit/Preisanker`. Einbau und Bedienung: [Haendlerprofit/LIESMICH.txt](Haendlerprofit/LIESMICH.txt).

Stand 14.11.2026: der Preisanker-Teil und das gemeinsame Fenster sind nur gegen eine nachgebaute
Spiel-API getestet.

## Test

```
lua5.1 tests/test.lua
```

`tests/spiel.lua` bildet die benutzte Spiel-API nach (Auktionshaus mit Drossel, Händler, Taschen).
