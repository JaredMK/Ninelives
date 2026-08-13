# Item unlock tuning

Edit the CHANGE TO MAKE column, hand it back, and I will apply it to `items.js` and re-export.

Sorted by TYPE, then by AT (earliest unlock first). Ungated items sit at the end of each type.

- Blank stat/at = available from the start. Fill in a stat + number to gate it.
- To un-gate a gated item, write `open` in the change column.
- AT values are NOT comparable across stats.
- 30 valid stats: dealsSurvived, runsPlayed, runsWon, bossesBeaten, endlessStagesReached,
  coinsEarnedLifetime, bestCoinsInClimb, bestCampaignScore, cardsBuried, samesCalled,
  correctSames, jokersPlayed, stickersApplied, pillarsPlaced, basesPlaced, removalsUsed,
  pilesLost, heartsPlayed, diamondsPlayed, clubsPlayed, spadesPlayed, perfectDeals,
  dealsWonRegular, dealsWonMaster, dealsWonLegendary, pinkyTipsSeen, zenGamesPlayed,
  zenEasyWon, zenMediumWon, zenHardWon

## STICKER — 49 items, 32 gated

| Item | Description | Stat | At | CHANGE TO MAKE |
|---|---|---|---|---|
| Payout | At deal end → earn coins equal to pile size if this card tops its pile | perfectDeals | 1 |  |
| Scout | When this card lands → peek at the next deck card | zenEasyWon | 1 |  |
| Tell | When this card lands → shows if the next deck card is higher, lower, or same | zenGamesPlayed | 1 |  |
| Random Rank | Set to random rank | runsPlayed | 3 |  |
| +2 Rank | +2 card rank (stops at Ace). | dealsWonRegular | 4 |  |
| Twin Spark | When this card lands → peek at the next card if another pile's top card matches this rank | zenGamesPlayed | 4 |  |
| Snowball Bury | When this card lands → bury X cards. X starts at 0, grows by 1 per correct placement, resets on a wrong guess | perfectDeals | 5 |  |
| Shuffle | When this card lands → optionally shuffle the pile | runsPlayed | 5 |  |
| Massive | When placed → +2 toward pile size | stickersApplied | 10 |  |
| Base Scout | When this card lands → peek at the next card if this column has no base | basesPlaced | 12 |  |
| Recharge Shield | When this card lands correctly → bank a Same Charge (max 1) | correctSames | 12 |  |
| −2 Rank | -2 card rank (stops at 2) | dealsSurvived | 12 |  |
| Pillar Scout | When this card lands → peek at the next card if this column has no pillar | pillarsPlaced | 12 |  |
| Quick Bury | When this card lands → bury 1 deck card under the pile | cardsBuried | 15 |  |
| Tap Power | When this card lands correctly → fire your equipped Same-Power | correctSames | 30 |  |
| Loose Change | When this card lands → +0–2 coins (random) | bestCoinsInClimb | 60 |  |
| Club Snob | When a ♣ lands on this card → bury 1 deck card under the pile | clubsPlayed | 60 |  |
| Diamond Snob | When a ♦ lands on this card → shuffle all piles | diamondsPlayed | 60 |  |
| Heart Snob | When a ♥ lands on this card → +2 coins | heartsPlayed | 60 |  |
| Spade Snob | When a ♠ lands on this card → peek at the next deck card | spadesPlayed | 60 |  |
| Collector | When this card lands → +1 coin per other sticker on this card | stickersApplied | 60 |  |
| Bury 2 | When this card lands → bury 2 deck cards under the pile. Costs 7 coins | cardsBuried | 90 |  |
| Compound | When this card lands → +X coins. X starts at 0, grows by 1 per correct placement | bestCampaignScore | 120 |  |
| Club Guard | Safe if this card lands on a ♣, or a ♣ lands on this card | clubsPlayed | 120 |  |
| Diamond Guard | Safe if this card lands on a ♦, or a ♦ lands on this card | diamondsPlayed | 120 |  |
| Heart Guard | Safe if this card lands on a ♥, or a ♥ lands on this card | heartsPlayed | 120 |  |
| Spade Guard | Safe if this card lands on a ♠, or a ♠ lands on this card | spadesPlayed | 120 |  |
| Deep Pockets | When this card lands → +1 coin per 10 cards left in the deck | bestCoinsInClimb | 140 |  |
| Club Roots | When this card lands → bury 1 deck card under each pile with a ♣ top card | clubsPlayed | 200 |  |
| Diamond Ripple | When this card lands → shuffle every other pile with a ♦ top card | diamondsPlayed | 200 |  |
| Heart Choir | When this card lands → +1 coin per other pile with a ♥ top card | heartsPlayed | 200 |  |
| Spade Whispers | When this card lands → the next X cards show a hint (higher/lower/same), where X = other piles with a ♠ top card | spadesPlayed | 200 |  |
| +1 Rank | +1 card rank (stops at Ace) | — | — |  |
| −1 Rank | -1 card rank (stops at 2) | — | — |  |
| Random Suit | Change to a random suit ♠♣♥♦ | — | — |  |
| Change to ♠ | Change suit to ♠ | — | — |  |
| Change to ♥ | Change suit to ♥ | — | — |  |
| Change to ♦ | Change suit to ♦ | — | — |  |
| Change to ♣ | Change suit to ♣ | — | — |  |
| Same-Safe | Safe if this card lands on a card of the same rank, or a card of the same rank lands on this card | — | — |  |
| Bonus Coin | When this card lands → +1 coin | — | — |  |
| Anchor | At deal end → exclude this pile from the smallest-pile score if this card tops its pile | — | — |  |
| Bury 1 | When this card lands → bury 1 deck card under the pile | — | — |  |
| Last Coin | When this card lands → +3 coins if it kills a pile | — | — |  |
| Heavy | When placed → +1 toward pile size | — | — |  |
| Wild Suit | Counts as every suit | — | — |  |
| Donate | When this card lands → move 1 buried card from this pile to the smallest pile | — | — |  |
| Leech *(cursed)* | Cursed — when this card lands → −1 coin | — | — |  |
| Leech Swarm *(cursed)* | Cursed — when this card lands → −1 coin | — | — |  |

## PILLAR — 28 items, 21 gated

| Item | Description | Stat | At | CHANGE TO MAKE |
|---|---|---|---|---|
| Last Rites | When a pile in this column dies → peek at the next card | dealsWonLegendary | 1 |  |
| Greedy | At deal end → +10 coins if every pile in this column survived and no other pillar is on the board | endlessStagesReached | 1 |  |
| Ditto | Mirrors the center column's pillar | runsWon | 1 |  |
| Streak Size | From the 3rd consecutive correct guess in this column → +1 pile size per guess. Resets on a wrong guess or any guess in another column | perfectDeals | 2 |  |
| Static | When a ♠ lands in this column → 50% chance to peek at the next card | zenMediumWon | 2 |  |
| Revive | When a pile in this column reaches 10 cards → revive one dead pile on the board | dealsWonMaster | 3 |  |
| Queen's Eye | When a royal ♠ (J/Q/K) lands correctly in this column → peek at the next card | zenEasyWon | 3 |  |
| Wild Aces | Aces count as high or low when landing in this column | jokersPlayed | 8 |  |
| Fibonacci | When a Fibonacci-rank card (A/2/3/5/8) lands correctly into this column → +1 coin | bossesBeaten | 10 |  |
| Diamond Distribution | When a ♦ lands in this column → redistribute all piles in this column to equal size | removalsUsed | 10 |  |
| Column Tie-Safe | Every pile in this column survives a tie | samesCalled | 12 |  |
| Prime | When a prime-rank card (2/3/5/7) lands correctly in this column → +1 coin | bossesBeaten | 20 |  |
| Second Wind | The first pile to die in this column is saved — but all its buried cards return to the deck | pilesLost | 25 |  |
| Insurance | At deal end → +10 coins if only one pile is alive board-wide and it's in this column | pilesLost | 50 |  |
| Dense Bury | When a ♣ with 2+ stickers lands correctly in this column → bury 1 deck card under that pile | stickersApplied | 80 |  |
| Excavator | At deal end → +1 coin per buried card in this column's largest pile with a ♥ top card | cardsBuried | 120 |  |
| Streak Bury | From the 4th consecutive correct guess in this column → bury 1 deck card per guess. Resets on a wrong guess or any guess in another column | cardsBuried | 140 |  |
| Fourth Seat | This column always starts the deal with 4 piles | bestCampaignScore | 150 |  |
| Highest Heart | At deal end → earn coins equal to the highest numbered ♥ top card in this column (2–10 face value, Ace pays 1, royals pay 0) | bestCampaignScore | 220 |  |
| 8 Bury | When a ♣ with no stickers lands correctly in this column → bury 1 deck card under that pile | clubsPlayed | 250 |  |
| Diamond Anchor | At deal end → exclude any pile in this column with a ♦ top card from the smallest-pile score | diamondsPlayed | 250 |  |
| Heart Bonus | When a ♥ lands in this column → +1 coin | — | — |  |
| Guardian | At deal end → +4 coins if every pile in this column survived | — | — |  |
| All Hearts | At deal end → +4 coins if every surviving pile in this column has a ♥ top card | — | — |  |
| Envy | At deal end → +2 coins per pile in this column with a ♥ top card | — | — |  |
| Massive Diamond | ♦ cards in this column count as +2 toward pile size | — | — |  |
| Shuffler | When a ♦ lands in this column → shuffle the other piles in this column | — | — |  |
| Gambler | At deal end → 50/50: +5 coins or nothing (requires a ♥ top card in this column) | — | — |  |

## BASE — 16 items, 13 gated

| Item | Description | Stat | At | CHANGE TO MAKE |
|---|---|---|---|---|
| Kamikaze | Kill a random ♠-topped pile in this column, then peek the next 3 cards | dealsWonMaster | 1 |  |
| Cast | Permanently set every top card's rank in this column to the bottom pile's rank | runsWon | 1 |  |
| Spade Peeker | Peek the next X cards, where X = piles in this column with a ♠ top card | zenHardWon | 1 |  |
| Suit Setter | Permanently set every top card's suit in this column to the bottom pile's suit | runsWon | 3 |  |
| Phoenix | Revive a random dead pile in this column with one fresh card (buried cards return to the deck) | pilesLost | 8 |  |
| Demolish | Choose a pillar → destroy it permanently, then peek the next 2 cards | pillarsPlaced | 18 |  |
| Reactor | Recharge your other two bases (never another Reactor) | basesPlaced | 25 |  |
| Recharge Cell | Bank a Same Charge (max 1) | correctSames | 28 |  |
| Power Surge | Fire your Same-Power on a random pile in this column | correctSames | 36 |  |
| Wild Sticker | Apply a random sticker to a random top card in this column | stickersApplied | 40 |  |
| Sticker Harvest | Choose a pile → bury 2 deck cards per sticker on its top card, then peel all those stickers | stickersApplied | 65 |  |
| Heart Demolish | Destroy every ♥-topped pile in this column. +4 coins per pile destroyed | heartsPlayed | 90 |  |
| Club Dig | Bury 1 deck card under each ♣-topped pile in this column | clubsPlayed | 300 |  |
| Upheaval | Shuffle every pile in this column | — | — |  |
| Ballast | Redistribute all piles in this column to equal size | — | — |  |
| Heart Tax | +1 coin per ♥ card in this column (top + buried, dead piles excluded) | — | — |  |

## SAMEPOWER — 6 items, 4 gated

| Item | Description | Stat | At | CHANGE TO MAKE |
|---|---|---|---|---|
| Same Heavy | Trigger: You make a correct Same
Effect: Add +1 pile size to every alive pile, and another +3 to the pile you called Same on | perfectDeals | 4 |  |
| Rekindle | Trigger: You make a correct Same
Effect: Revive the largest dead pile on the board | correctSames | 18 |  |
| Burrow | Trigger: You make a correct Same
Effect: Bury 1 card under every alive pile | samesCalled | 30 |  |
| Link Shuffler | Trigger: You make a correct Same
Effect: Shuffle every alive pile | samesCalled | 35 |  |
| Dividend | Trigger: You make a correct Same
Effect: Gain 1 coin for each alive pile on the board | — | — |  |
| Same Peeker | Trigger: You make a correct Same
Effect: Peek at the next upcoming card | — | — |  |

## PACK — 4 items, 2 gated

| Item | Description | Stat | At | CHANGE TO MAKE |
|---|---|---|---|---|
| Large Card Pack | Reveals 5 random cards. Keep 2 to swap into your deck before a deal, replacing a card of your choice. | pinkyTipsSeen | 5 |  |
| Large Sticker Pack | Reveals 5 random stickers. Keep 2 for your inventory. The rest are discarded. | stickersApplied | 45 |  |
| Small Card Pack | Reveals 3 random cards. Keep 1 to swap into your deck before a deal, replacing a card of your choice. | — | — |  |
| Small Sticker Pack | Reveals 3 random stickers. Keep 1 to add to a card. | — | — |  |
