# Item Help Text Review — items.js

Generated from `items.js` @ branch `ios-port` (HEAD b9d47b5, v6.53). Every
sellable item is listed below, grouped by class and sorted alphabetically by
display name within each group.

## How to edit this document

- Each item is one block; blocks are separated by `---`.
- The line you edit is the one prefixed `TEXT:` — it holds the item's current
  `description` **verbatim** (JSON-quoted, so `\n` inside a Same-Power text is
  a real newline in the data). To retcon a description, edit the TEXT line in
  place; the changes will later be applied back to the matching
  `description:` field in `items.js` (matched by the block's `id`, never by
  the label).
- Do not edit `id` lines — ids are stable keys (saves/offers/tests bind to
  them). `label` is the player-facing name and is safe to rename.
- `[CURSED]` marks cursed stickers (price 0, never sold — inflicted via
  mystery/Old-Joker pathways only).
- Numbers in TEXT lines are read live from the item's tunable fields in
  `items.js` by the game — if you change a number here, the matching knob in
  `items.js` must change with it (or the text lies).
- The FLAGS section at the bottom lists every verified description/code
  disagreement, empty texts, and duplicate texts.

Inventory: 58 stickers (13 cursed) · 36 pillars · 22 bases · 9 same-powers ·
4 packs · 3 store pseudo-items = **132 entries**.

## STICKERS (58)

### +1 Rank
- id: `rankUp`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "+1 card rank (stops at Ace)"

---

### +2 Rank
- id: `rankUp2`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "+2 card rank (stops at Ace)"

---

### −1 Rank
- id: `rankDown`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "-1 card rank (stops at 2)"

---

### −2 Rank
- id: `rankDown2`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "-2 card rank (stops at 2)"

---

### Anchor
- id: `anchor`
- class: sticker
- rarity: common
- cost: 2 coins
TEXT: "At deal end → exclude pile from the smallest-pile score if this card is on top"

---

### Base Drain  `[CURSED]`
- id: `drainBase`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. The column's Base is drained"

---

### Base Scout
- id: `baseScout`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "Peek at the next card if this column has no base"

---

### Bonus Coin
- id: `gainCoin`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "+1 coin"

---

### Change to ♠
- id: `changeSuitSpade`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Change suit to ♠"

---

### Change to ♣
- id: `changeSuitClub`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Change suit to ♣"

---

### Change to ♥
- id: `changeSuitHeart`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Change suit to ♥"

---

### Change to ♦
- id: `changeSuitDiamond`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Change suit to ♦"

---

### Club Guard
- id: `clubGuard`
- class: sticker
- rarity: uncommon
- cost: 5 coins
TEXT: "Safe if this card lands on a ♣, or a ♣ lands on this card"

---

### Club Roots
- id: `clubRoots`
- class: sticker
- rarity: rare
- cost: 8 coins
TEXT: "Bury 1 card under each pile with a ♣ top card"

---

### Club Snob
- id: `clubSnob`
- class: sticker
- rarity: uncommon
- cost: 10 coins
TEXT: "When a ♣ lands on this card, or this card lands on a ♣ → bury 1 deck card under the pile"

---

### Collector
- id: `collector`
- class: sticker
- rarity: uncommon
- cost: 1 coins
TEXT: "+1 coin per other sticker on this card"

---

### Compound
- id: `compound`
- class: sticker
- rarity: rare
- cost: 6 coins
TEXT: "+X coins. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess"

---

### Deep Pockets
- id: `deepPockets`
- class: sticker
- rarity: uncommon
- cost: 3 coins
TEXT: "+1 coin per 10 cards left in the deck"

---

### Diamond Guard
- id: `diamondGuard`
- class: sticker
- rarity: uncommon
- cost: 5 coins
TEXT: "Safe if this card lands on a ♦, or a ♦ lands on this card"

---

### Diamond Ripple
- id: `diamondRipple`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "Shuffle every other pile with a ♦ top card"

---

### Diamond Snob
- id: `diamondSnob`
- class: sticker
- rarity: uncommon
- cost: 6 coins
TEXT: "When a ♦ lands on this card, or this card lands on a ♦ → shuffle every pile"

---

### Donate
- id: `donate`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Move 1 buried card from this pile to the smallest pile"

---

### Flatline  `[CURSED]`
- id: `flatline`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. While this card is a pile's top card, that pile size is 1"

---

### Heart Choir
- id: `heartChoir`
- class: sticker
- rarity: uncommon
- cost: 3 coins
TEXT: "+1 coin per each pile with a ♥ top card"

---

### Heart Guard
- id: `heartGuard`
- class: sticker
- rarity: uncommon
- cost: 5 coins
TEXT: "Safe if this card lands on a ♥, or a ♥ lands on this card"

---

### Heart Snob
- id: `heartSnob`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "When a ♥ lands on this card, or this card lands on a ♥ → +2 coins"

---

### Heavy
- id: `heavy`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "+1 pile size"

---

### Jammer  `[CURSED]`
- id: `jammer`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. While this is a pile's top card, the column's Pillar does not work"

---

### Last Coin
- id: `deathBounty`
- class: sticker
- rarity: common
- cost: 2 coins
TEXT: "+3 coins if it kills a pile"

---

### Leech  `[CURSED]`
- id: `leech`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. −3 coins"

---

### Loose Change
- id: `looseChange`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "+0–3 coins (random)"

---

### Magnet  `[CURSED]`
- id: `magnet`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. While this is a pile's top card, your next guess must be played there"

---

### Malfunction  `[CURSED]`
- id: `malfunction`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. 10% chance this card kills the pile anyway, even if the guess is correct"

---

### Massive
- id: `massive`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "+2 pile size"

---

### Mute  `[CURSED]`
- id: `mute`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. While this is a pile's top card, Same cannot be called there"

---

### Payout
- id: `extraCoin`
- class: sticker
- rarity: uncommon
- cost: 3 coins
TEXT: "At deal end if this card tops its pile  → earn coins equal to pile size"

---

### Peeler  `[CURSED]`
- id: `peeler`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. Any card this card touches loses ALL of its stickers"

---

### Pillar Scout
- id: `pillarScout`
- class: sticker
- rarity: uncommon
- cost: 2 coins
TEXT: "Peek the next card if this column has no pillar"

---

### Quick Bury
- id: `quickBury`
- class: sticker
- rarity: uncommon
- cost: 7 coins
TEXT: "When a card lands on this card → bury 1 card under the pile"

---

### Random Rank
- id: `randomFixedValue`
- class: sticker
- rarity: uncommon
- cost: 1 coins
TEXT: "Change to random rank"

---

### Random Suit
- id: `changeSuitRandom`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Change to random suit"

---

### Recharge Shield
- id: `rechargeSameShield`
- class: sticker
- rarity: rare
- cost: 8 coins
TEXT: "Charge the Same Shield"

---

### Saboteur  `[CURSED]`
- id: `saboteur`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. 10% chance the column's Base or Pillar is destroyed"

---

### Same-Safe
- id: `tieSafe`
- class: sticker
- rarity: common
- cost: 2 coins
TEXT: "Safe if this card lands on a card of the same rank, or a card of the same rank lands on this card"

---

### Scout
- id: `revealNext`
- class: sticker
- rarity: rare
- cost: 10 coins
TEXT: "Peek at the next deck card"

---

### Shield Drain  `[CURSED]`
- id: `drainShield`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. Drain the Same Shield"

---

### Shrink  `[CURSED]`
- id: `shrink`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. This card counts −1 toward pile size"

---

### Shuffle
- id: `shuffle`
- class: sticker
- rarity: uncommon
- cost: 1 coins
TEXT: "Optionally shuffle the pile"

---

### Snowball Bury
- id: `snowball`
- class: sticker
- rarity: rare
- cost: 10 coins
TEXT: "Bury X cards. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess"

---

### Spade Guard
- id: `suitImmunity`
- class: sticker
- rarity: uncommon
- cost: 5 coins
TEXT: "Safe if this card lands on a ♠, or a ♠ lands on this card"

---

### Spade Snob
- id: `suitSnob`
- class: sticker
- rarity: uncommon
- cost: 4 coins
TEXT: "When a ♠ lands on this card, or this card lands on a ♠ → peek at the next card"

---

### Spade Whispers
- id: `spadeWhispers`
- class: sticker
- rarity: rare
- cost: 8 coins
TEXT: "The next X cards show a hint (higher/lower/same), where X = other piles with a ♠ top card"

---

### Spoiler  `[CURSED]`
- id: `spoiler`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. Reset bonus coins earned this deal to 0"

---

### Tap Power
- id: `activateSamePower`
- class: sticker
- rarity: rare
- cost: 6 coins
TEXT: "Fire your Same-Power"

---

### Tell
- id: `tell`
- class: sticker
- rarity: uncommon
- cost: 4 coins
TEXT: "Shows if the next deck card is higher, lower, or same"

---

### Trapdoor  `[CURSED]`
- id: `trapdoor`
- class: sticker
- rarity: common
- cost: 0 coins
TEXT: "Cursed. When it lands, the card at the BOTTOM of the pile returns to the deck"

---

### Twin Spark
- id: `twinSpark`
- class: sticker
- rarity: uncommon
- cost: 3 coins
TEXT: "Peek at the next card if another pile's top card matches this rank"

---

### Wild Suit
- id: `wildSuit`
- class: sticker
- rarity: common
- cost: 1 coins
TEXT: "Counts as every suit"

## PILLARS (36)

### All Hearts
- id: `allHeartsCoin`
- class: pillar
- rarity: common
- cost: 4 coins
TEXT: "At deal end → +4 coins if every surviving pile in this column has a ♥ top card"

---

### Bouncer
- id: `twoWard`
- class: pillar
- rarity: uncommon
- cost: 5 coins
TEXT: "30% chance to turn away a Just a Two mystery outcome. No effect during deal"

---

### Bulk Rate
- id: `bulkRate`
- class: pillar
- rarity: uncommon
- cost: 6 coins
TEXT: "The store's Purge price climbs by 1 instead of 2. No effect during deal"

---

### Clean Bury
- id: `clubTribute`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "When a ♣ with no stickers lands in this column → bury 1 card under that pile"

---

### Column Tie-Safe
- id: `columnTieSafe`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "Any tie is safe in this column"

---

### Crowd Favorite
- id: `crowdFavorite`
- class: pillar
- rarity: rare
- cost: 6 coins
TEXT: "When a {rank} lands correctly in this column → +2 coins"

---

### Dense Bury
- id: `denseBury`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "When a ♣ with 2+ stickers lands correctly in this column → bury 1 card under that pile"

---

### Diamond Anchor
- id: `diamondAnchor`
- class: pillar
- rarity: rare
- cost: 6 coins
TEXT: "At deal end → exclude any pile in this column with a ♦ top card from the smallest-pile score"

---

### Diamond Distribution
- id: `diamondDistribution`
- class: pillar
- rarity: uncommon
- cost: 3 coins
TEXT: "When a ♦ lands in this column → make all piles in this column equal size"

---

### Ditto
- id: `ditto`
- class: pillar
- rarity: rare
- cost: 5 coins
TEXT: "Mirrors the center column's pillar"

---

### Envy
- id: `envy`
- class: pillar
- rarity: common
- cost: 4 coins
TEXT: "At deal end → +2 coins per pile in this column with a ♥ top card"

---

### Excavator
- id: `excavator`
- class: pillar
- rarity: uncommon
- cost: 3 coins
TEXT: "At deal end → +1 coin per buried card in this column's largest pile with a ♥ top card"

---

### Fibonacci
- id: `fibonacci`
- class: pillar
- rarity: uncommon
- cost: 4 coins
TEXT: "When a Fibonacci-rank card (A/2/3/5/8) lands correctly in this column → +1 coin"

---

### Flypaper
- id: `flypaper`
- class: pillar
- rarity: uncommon
- cost: 6 coins
TEXT: "When a card lands correctly in this column → 5% chance it gains a random sticker"

---

### Fourth Seat
- id: `fourthSeat`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "This column starts the deal with 1 extra pile (up to 4)"

---

### Freebie
- id: `freebie`
- class: pillar
- rarity: rare
- cost: 9 coins
TEXT: "One random item in every store costs 0 coins. No effect during deal"

---

### Gambler
- id: `gambler`
- class: pillar
- rarity: uncommon
- cost: 5 coins
TEXT: "At deal end → 50/50: +3 coins or nothing"

---

### Greedy
- id: `greedy`
- class: pillar
- rarity: rare
- cost: 5 coins
TEXT: "At deal end → +4 coins if this is the only equipped pillar"

---

### Guardian
- id: `columnGuardian`
- class: pillar
- rarity: uncommon
- cost: 4 coins
TEXT: "At deal end → +4 coins if every pile in this column survived"

---

### Heart Bonus
- id: `heartBounty`
- class: pillar
- rarity: uncommon
- cost: 5 coins
TEXT: "When a ♥ lands in this column → +1 coin"

---

### Highest Heart
- id: `highestEven`
- class: pillar
- rarity: rare
- cost: 8 coins
TEXT: "At deal end → earn coins equal to the highest numbered ♥ top card in this column (2–10 face value, Ace pays 1, royals pay 0)"

---

### Insurance
- id: `insurance`
- class: pillar
- rarity: rare
- cost: 4 coins
TEXT: "At deal end → +5 coins if only one pile is alive"

---

### Last Licks
- id: `lastLicks`
- class: pillar
- rarity: uncommon
- cost: 4 coins
TEXT: "At deal end → +3 coins if no pile in this column survived"

---

### Last Rites
- id: `lastRites`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "When a pile in this column dies → peek the next card"

---

### Massive Diamond
- id: `stickerCount`
- class: pillar
- rarity: uncommon
- cost: 4 coins
TEXT: "♦ cards in this column count as +2 toward pile size"

---

### Prime
- id: `prime`
- class: pillar
- rarity: rare
- cost: 3 coins
TEXT: "When a prime-rank card (2/3/5/7) lands correctly in this column → +1 coin"

---

### Queen's Eye
- id: `queensEye`
- class: pillar
- rarity: uncommon
- cost: 4 coins
TEXT: "When a royal ♠ (J/Q/K) lands in this column → peek at the next card"

---

### Rare Hunter
- id: `rareHunter`
- class: pillar
- rarity: rare
- cost: 8 coins
TEXT: "Rare items appear in the store twice as often. No effect during deal"

---

### Revive
- id: `revive`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "When a pile in this column reaches 10 cards → revive one dead pile"

---

### Second Wind
- id: `secondWind`
- class: pillar
- rarity: rare
- cost: 6 coins
TEXT: "When a pile in this column dies → 25% chance it is saved, but all its buried cards return to the deck"

---

### Shuffler
- id: `royalCourt`
- class: pillar
- rarity: uncommon
- cost: 3 coins
TEXT: "When a ♦ lands in this column → shuffle the other piles in this column"

---

### Static
- id: `static`
- class: pillar
- rarity: rare
- cost: 3 coins
TEXT: "When a ♠ lands in this column → 50% chance to peek at the next card"

---

### Streak Bury
- id: `streakTribute`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "From the 4th consecutive correct guess in this column → bury 1 card per guess. Resets on a wrong guess or any guess in another column"

---

### Streak Size
- id: `streakBank`
- class: pillar
- rarity: rare
- cost: 4 coins
TEXT: "From the 3rd consecutive correct guess in this column → +1 pile size per guess. Resets on a wrong guess or any guess in another column"

---

### Underdog
- id: `underdog`
- class: pillar
- rarity: rare
- cost: 6 coins
TEXT: "When a {rank} lands correctly in this column → bury 1 deck card under that pile"

---

### Wild Aces
- id: `wildAces`
- class: pillar
- rarity: rare
- cost: 10 coins
TEXT: "Aces count as high or low in this column"

## BASES (22)

### Ballast
- id: `evenOut`
- class: base
- rarity: common
- cost: 5 coins
TEXT: "Make all piles in this column equal size"

---

### Cast
- id: `setValue`
- class: base
- rarity: rare
- cost: 10 coins
TEXT: "Permanently set every top card's rank in this column to the bottom pile's rank"

---

### Club Dig
- id: `clubDig`
- class: base
- rarity: rare
- cost: 8 coins
TEXT: "Bury 1 card under each ♣-topped pile in this column"

---

### Club Oracle
- id: `clubOracle`
- class: base
- rarity: uncommon
- cost: 8 coins
TEXT: "Put a tell marker on each ♣-topped pile in this column for the next draw. Tell marker shows if the next card is higher, lower, or same"

---

### Demolish
- id: `demolish`
- class: base
- rarity: uncommon
- cost: 8 coins
TEXT: "Destroy this column's pillar permanently, then peek the next 3 cards"

---

### Empty Purse
- id: `emptyPurse`
- class: base
- rarity: rare
- cost: 5 coins
TEXT: "Spend all the coins in your purse and peek one card for every 10 coins spent"

---

### Escape Hatch
- id: `ambushOut`
- class: base
- rarity: rare
- cost: 8 coins
TEXT: "Only usable in an ambush → clear the deal instantly. No effect during deal"

---

### Heart Demolish
- id: `heartDemolish`
- class: base
- rarity: uncommon
- cost: 5 coins
TEXT: "Destroy every ♥-topped pile in this column. +4 coins per pile destroyed"

---

### Heart Tax
- id: `tax`
- class: base
- rarity: uncommon
- cost: 5 coins
TEXT: "+1 coin per ♥ card in this column"

---

### Kamikaze
- id: `kamikaze`
- class: base
- rarity: rare
- cost: 8 coins
TEXT: "Kill a random ♠-topped pile in this column, → peek the next 2 cards"

---

### Last Resort
- id: `lastResort`
- class: base
- rarity: rare
- cost: 10 coins
TEXT: "In a non-boss deal, bury the whole deck under a pile in this column and win instantly. Any Base nearby is destroyed"

---

### Lone Eye
- id: `lonePeek`
- class: base
- rarity: rare
- cost: 10 coins
TEXT: "Peek the next card. Only works while no Same-Power is equipped"

---

### Phoenix
- id: `revive`
- class: base
- rarity: uncommon
- cost: 7 coins
TEXT: "Revive a random dead pile in this column. Buried cards return to the deck"

---

### Power Surge
- id: `activateSame`
- class: base
- rarity: rare
- cost: 10 coins
TEXT: "Activate your Same-Power"

---

### Reactor
- id: `refreshBases`
- class: base
- rarity: rare
- cost: 9 coins
TEXT: "Recharge your other two bases"

---

### Recharge Cell
- id: `rechargeSame`
- class: base
- rarity: rare
- cost: 10 coins
TEXT: "Charge the Same Shield"

---

### Same Tell
- id: `sameTell`
- class: base
- rarity: uncommon
- cost: 5 coins
TEXT: "Tell if the next card is the same rank as a top card"

---

### Spade Peeker
- id: `spadePeek`
- class: base
- rarity: uncommon
- cost: 7 coins
TEXT: "Peek the next card. Requires every pile in this column has a ♠ on top"

---

### Sticker Harvest
- id: `stickerHarvest`
- class: base
- rarity: uncommon
- cost: 6 coins
TEXT: "Choose a pile → bury 2 cards per sticker on its top card, then peel all those stickers"

---

### Suit Setter
- id: `setSuit`
- class: base
- rarity: rare
- cost: 5 coins
TEXT: "Permanently set every top card's suit in this column to the bottom pile's suit"

---

### Upheaval
- id: `shuffleColumn`
- class: base
- rarity: common
- cost: 5 coins
TEXT: "Shuffle every pile in this column"

---

### Wild Sticker
- id: `randomSticker`
- class: base
- rarity: uncommon
- cost: 10 coins
TEXT: "Apply a random sticker to a random top card in this column"

## SAME-POWERS (9)

### Burrow
- id: `linkBury`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Bury 1 card under every pile with a {suit} top card"

---

### Dividend
- id: `linkCoins`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Gain 1 coin for each alive pile"

---

### Link Shuffler
- id: `linkShuffle`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Shuffle every alive pile"

---

### Long Odds
- id: `linkPurge`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "25% chance to permanently purge a card from the deck"

---

### Rekindle
- id: `linkRevive`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Revive a dead pile"

---

### Same Heavy
- id: `linkHeavy`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Add +1 pile size to every pile, and +3 to the pile you called Same on"

---

### Same Peeker
- id: `samePeek`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Peek the next card"

---

### Second Sight
- id: `linkTell`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "The next X cards show a tell (higher/lower/same indicator) hint, where X is the number of alive piles with a {color} top card"

---

### Sticker Spray
- id: `linkSticker`
- class: same-power
- rarity: rare
- cost: 9 coins
TEXT: "Apply a random sticker to every top card in this column"

## PACKS (4)

### Large Card Pack
- id: `cardPack`
- class: pack
- rarity: uncommon
- cost: 4 coins
TEXT: "Reveals 5 random cards. Keep 2 to swap into your deck"

---

### Large Sticker Pack
- id: `largeStickerPack`
- class: pack
- rarity: common
- cost: 6 coins
TEXT: "Reveals 5 random stickers. Keep 2"

---

### Small Card Pack
- id: `smallCardPack`
- class: pack
- rarity: common
- cost: 2 coins
TEXT: "Reveals 3 random cards. Keep 1 to swap into your deck"

---

### Small Sticker Pack
- id: `stickerPack`
- class: pack
- rarity: common
- cost: 3 coins
TEXT: "Reveals 3 random stickers. Keep 1"

## STORE PSEUDO-ITEMS (configured under `store`, not in a class array)

### Mystery Same-Power
- id: `store.mysterySamePower`
- class: store pseudo-item
- rarity: —
- cost: 10 coins
TEXT: "Purchase to reveal"

---

### Card
- id: `store.card`
- class: store pseudo-item
- rarity: —
- cost: 3 coins
TEXT: "A single card. Swap it into your deck"

---

### Purge
- id: `store.removal`
- class: store pseudo-item
- rarity: —
- cost: 5 coins
TEXT: "Permanently remove a card from your deck. Purge price climbs each time"


---

# FLAGS

Everything below was verified against the code on this branch (HEAD b9d47b5).
"web" = `index.html`; "iOS" = `ios/GameCore/*.swift`. Where a flag rests on an
absence I grepped for, the search terms are named so it can be re-checked.

## 1. MISMATCHES (description vs. verified behavior)

### A. Whole features the web engine never implements (iOS-only)

The single biggest finding: a large block of items.js entries has **no
implementation in the web engine at all** — the ids, effects and labels do not
appear anywhere in `index.html` (verified by searching each id/effect/label
string; zero hits). Their behaviors exist only in the iOS port. If the store
offers these on web, the bought item is inert there. Descriptions match the
iOS implementation in each case, so the text itself is fine — the web code is
what's missing. (Branch is `ios-port`; this may be intentional mid-port
staging, but from items.js' "single source of truth" seat it is a
description-vs-web-code disagreement.)

- **5 BASES — zero occurrences in `index.html`** of `sameTell` / `lonePeek` /
  `emptyPurse` / `lastResort` / `ambushWin`:
  - `sameTell` "Same Tell" — iOS: `ios/GameCore/GameEngineBases.swift:255-273`
    (marks the matching top with `=`; silence on no match — matches TEXT).
  - `lonePeek` "Lone Eye" — iOS: `GameEngineBases.swift:225-231`, availability
    gate `run.samePower == nil` at line 52 — matches TEXT.
  - `emptyPurse` "Empty Purse" — iOS: `GameEngineBases.swift:246-253` — matches TEXT.
  - `lastResort` "Last Resort" — iOS: `GameEngineBases.swift:233-244`, boss
    seal at line 54 + reason string at 118-121 — matches TEXT.
  - `ambushOut` "Escape Hatch" — iOS: `GameEngineBases.swift:332`, gate
    `runConfig.isAmbush` at line 59 — matches TEXT.
  - Web's base availability switch (`index.html:13293-13318`) and execution
    switch (`index.html:13370-13637`) end in `default: return false/null` —
    these five effects are not cases in either.
- **7 PILLARS — zero occurrences in `index.html`** of `flypaper` / `twoWard` /
  `bulkRate` / `purgeStepDiscount` / `freebie` / `rareHunter` / `underdog` /
  `crowdFavorite` / `rankBury` / `rankCoin` / `pillarRankVariants`:
  - `flypaper` "Flypaper" — iOS: `ios/GameCore/GameEngineEffects.swift:22`.
  - `twoWard` "Bouncer" — iOS: `ios/GameCore/CampaignState.swift:934-937`.
  - `bulkRate` "Bulk Rate" — iOS: `CampaignState.swift:1145`.
  - `freebie` "Freebie" — iOS: `CampaignState.swift:1520,1606`.
  - `rareHunter` "Rare Hunter" — iOS: `CampaignState.swift:1171`.
  - `underdog` "Underdog" + `crowdFavorite` "Crowd Favorite" — iOS:
    `GameEngineEffects.swift:33,37`; the `{rank}` template is substituted only
    natively (`CampaignState.swift:225-235`). On web these two would also
    render the literal text "{rank}" — no substitution code exists in
    `index.html` (no occurrence of `{rank}`/`{suit}`/`{color}` anywhere).
- **12 CURSED STICKERS — zero occurrences in `index.html`** of `trapdoor` /
  `spoiler` / `drainShield` / `flatline` / `magnet` / `jammer` / `peeler` /
  `drainBase` / `malfunction` / `saboteur` / `mute` (behavior) / `shrink`
  (behavior). Only `leech` (behavior `tributeCoin`) has web code
  (`index.html:12783-12791`). The full curse overhaul lives in
  `ios/GameCore/GameEngineCurses.swift` (+ `GameEngine.swift:554-613`), which
  matches the descriptions. Web tests don't cover them either (no `tests/*.mjs`
  references these ids).

### B. Same-Powers: web implements 6 of 9, and Burrow differs

`index.html:13689-13757` (`fireSamePower`) has cases only for `linkBury`,
`linkRevive`, `linkCoins`, `linkShuffle`, `samePeek`, `linkHeavy`. Zero
occurrences of `linkTell` / `linkSticker` / `linkPurge` in `index.html`:

- `linkTell` "Second Sight" — TEXT: "…The next X cards show a tell … X is the
  number of alive piles with a {color} top card". Web: does nothing. iOS
  implements it (`ios/GameCore/GameEngineBases.swift:577-602`) including the
  climb-fixed red/black roll — matches TEXT.
- `linkSticker` "Sticker Spray" — TEXT: "…Apply a random sticker to every top
  card in this column". Web: does nothing. iOS
  (`GameEngineBases.swift:604-624`) sprays the called pile's column — matches TEXT.
- `linkPurge` "Long Odds" — TEXT: "…25% chance to purge a random card from the
  rest of the deck". Web: does nothing. iOS (`GameEngineBases.swift:626-636`,
  `chance` fallback 0.25 = def) — matches TEXT.
- `linkBury` "Burrow" — TEXT: "…Bury 1 card under every alive pile with a
  {suit} top card". iOS filters targets by the climb-fixed rolled suit
  (`GameEngineBases.swift:526-539`, roll at `CampaignState.swift:197`) —
  matches TEXT. **Web buries under EVERY alive pile, no suit filter**
  (`index.html:13695-13702`), and never substitutes `{suit}` (string absent
  from `index.html`) — web players would see the literal "{suit}" and get a
  stronger, suit-blind effect. Mismatch on the web side.
- Note (data comment, not TEXT): the `samePowers` header comment in
  `items.js:569-572` still says powers act on "piles DIRECTLY LINKED (via the
  synapse network)" — stale since v5.66 made all powers board-wide
  (`index.html:13670-13674`, `GameEngineBases.swift:508-510`).

### C. Items whose behavior the v6.51–6.53 rework changed — verified results

- `compound` "Compound" — TEXT: "+X coins. X starts at 0, grows by 1 per
  correct placement, resets on a wrong guess". **Matches.** Correct guess
  against the carrying top pays `(hits−1)×step` (`index.html:14248-14254`);
  a wrong guess against that top resets hits to 0
  (`index.html:14280-14283`; iOS `GameEngine.swift:545-552`).
- The Snob family (`suitSnob`, `heartSnob`, `diamondSnob`, `clubSnob`) —
  bidirectional TEXT ("When a X lands on this card, or this card lands on a
  X"). **Matches.** Both directions implemented at `index.html:12878-12948`
  (forward = snob on pile top, reverse = snob on drawn card).
- `demolish` "Demolish" — TEXT: "Destroy this column's pillar permanently,
  then peek the next 3 cards". **Matches.** Own column only, `peekCount` 3
  (`index.html:13588-13601`, availability gate `:13308`;
  iOS `GameEngineBases.swift:177-178` comment).
- `kamikaze` "Kamikaze" — TEXT: "Kill a random ♠-topped pile in this column,
  then peek the next 2 cards". **Matches** def `peekCount: 2`
  (`index.html:13371-13390`; iOS `GameEngineBases.swift:189-203`).
- `clubOracle` "Club Oracle" — TEXT: "Put a tell marker on each club pile in
  this column for the next draw" **Matches** — every alive ♣-topped pile in
  the column gets the tell (`index.html:13420-13430`;
  iOS `GameEngineBases.swift:275+`).
- `looseChange` "Loose Change" — TEXT: "+0–3 coins (random)". **Matches** def
  `max: 3` — roll is `floor(rng()×(max+1))` per sticker on the landed card
  (`index.html:12873-12877`).
- `spadePeek` "Spade Peeker" — TEXT: "Peek the next card. Only fires when
  EVERY pile in this column has a ♠ on top". **iOS matches**
  (`GameEngineBases.swift:37` availability `alive.allSatisfy ♠`, `:217-223`
  exactly one peek). **Web disagrees twice**: availability is ANY ♠ top
  (`index.html:13298` `alive.some(...)`), and it peeks X cards where X = the
  number of ♠-topped piles (`index.html:13409-13418`), not "the next card".
- `secondWind` "Second Wind" — TEXT: "Each pile that dies in this column has a
  25% chance to be saved, but all its buried cards return to the deck".
  **iOS matches**: every death rolls `saveChance` 0.25, unlimited
  (`ios/GameCore/GameEngine.swift:637-650`). **Web disagrees twice**: the save
  is GUARANTEED (no chance roll — `saveChance` is never read on web) and it
  fires only ONCE per column per run (`index.html:14352-14357`, gated on
  `!run.secondWindUsed[col]`; comment says "the first pile to die in this
  column each run revives once").
- Touch curses fire only on correct landings (v6.52/6.53 fatal-landing audit)
  — **code confirmed**: `curseTouch` is called only from the correct-landing
  and malfunction branches (`ios/GameCore/GameEngine.swift:568-580`; explicit
  no-call comments at `:660-662` and `:669-672`). Descriptions are mostly
  compatible, but see wording notes below.

### D. Trigger/direction wording (verified in code; smaller issues)

- **"lands" vs "lands correctly"** — four pillar TEXTs omit "correctly" while
  their siblings include it, but all four fire ONLY on correct landings:
  - `heartBounty` "Heart Bonus": "When a ♥ lands in this column → +1 coin" —
    gated on `correct` (`index.html:14261`; iOS `GameEngine.swift:529`).
  - `royalCourt` "Shuffler": "When a ♦ lands in this column → shuffle the
    other piles in this column" — runs only from the correct branch
    (`index.html:12566`, called at `:14313`; iOS `GameEngineEffects.swift:45`,
    called from the correct branch `GameEngine.swift:593`).
  - `static` "Static": "When a ♠ lands in this column → 50% chance to peek…" —
    gated on `correct` (`index.html:14196`; iOS `GameEngine.swift:468`).
  - `diamondDistribution` "Diamond Distribution": "When a ♦ lands in this
    column → redistribute…" — correct-only (`index.html:12575`;
    iOS `GameEngineEffects.swift:60`).
- **Curse trigger wording** — several curses fire on (correct) landing, but
  their TEXT doesn't say when: `spoiler` "Bonus coins earned this deal reset
  to 0", `drainShield` "Your Same Charge drains", `drainBase` "The column's
  Base is spent for the deal", `saboteur` "10% chance the column's Base or
  Pillar is destroyed" — all fire inside `curseTouch`, i.e. only when the
  carrying card lands correctly (`ios/GameCore/GameEngineCurses.swift:42-105`).
  `peeler` "Any card this card touches loses ALL of its stickers" — code:
  both directions, correct landings only, mutual peelers strip each other,
  curses included (`GameEngineCurses.swift:48-55`). `trapdoor` "When it lands,
  the card at the BOTTOM of its pile returns to the deck" — code: correct
  landings only, one bottom card per Trapdoor instance, pile keeps its top
  (`GameEngine.swift:597-613`). "Touches"/"lands" read broader than the
  correct-landing-only rule the fatal-landing audit established.
- `magnet` "Magnet" — TEXT: "While this is a pile's top card, your next guess
  must be played there". Code: the constraint applies to EVERY guess while a
  magnet tops an alive pile (not just the "next" one), and with 2+ magnets any
  of them satisfies it (`GameEngineCurses.swift:24-31`). Minor.
- Suit-synergy stickers (`heartChoir`, `diamondRipple`, `clubRoots`,
  `spadeWhispers`) — TEXTs state no trigger at all; code fires them when the
  CARRYING card lands correctly, scaled by OTHER piles (`index.html:12950-13006`).
  Consistent with the terse style of `gainCoin` "+1 coin", but e.g.
  Heart Choir's "+1 coin per other pile with a ♥ top card" can be misread as a
  deal-end aura. Convention-consistent — listed for awareness, no strong flag.
- Verified OK (numbers checked against def + code): `leech` −3 (def value 3,
  `index.html:12785`), `deathBounty` +3 on kill (`index.html:14382-14384`),
  `extraCoin` pile-size payout (`index.html:12460-12471`), `anchor`
  (`index.html:12425,14095-14096`), `heavy`/`massive` size weight
  (`index.html:12356`), `collector`, `deepPockets` per-10, `quickBury`,
  `snowball`, `tell`, `twinSpark`, `pillarScout`/`baseScout` (own-column slot
  check, `index.html:13045-13053`), `donate` (now AUTOMATIC bottom-card move,
  `index.html:13085-13100` — TEXT "Move 1 buried card…" still fine),
  `shuffle` (optional offer), `tieSafe` + 4 Guards (bidirectional,
  `index.html:14175-14176,14340-14351`), `streakBank` (3rd: +1, 4th: +2… —
  "per guess" escalation, `index.html:14084-14087`), `streakTribute` (flat 1
  from the 4th), `fourthSeat`, `columnTieSafe`, `lastLicks`…
  (all scoring pillars `index.html:13805-13894`), `highestEven` (A=1,
  royals=0, `index.html:13845-13863`), `fibonacci`/`prime`/`queensEye`
  rank sets, `clubTribute` (sticker-free ♣)/`denseBury` (2+ stickers),
  `greedy` (sole pillar), `insurance`, `excavator`, `gambler` (50/50, +5),
  `wildAces`, `revive` (trigger 10), `stickerCount` "Massive Diamond" (+2/♦),
  `setValue`/`setSuit` (bottom = last alive pile in column,
  `index.html:13504-13553`), `stickerHarvest` (2 per sticker, then peel),
  `refreshBases`, `clubDig`, `heartDemolish` (+4/pile), `tax` (+1/♥ card),
  `evenOut`, `shuffleColumn`, `randomSticker`, `rechargeSame`, `activateSame`,
  `samePeek`, `linkRevive`, `linkCoins`, `linkShuffle`, `linkHeavy` (+1/+3),
  all 4 packs, `store.card` (+1/sticker), `store.removal`, and
  `store.mysterySamePower` (price 10, "Purchase to reveal").

### E. Stale code-fallback defaults (not TEXT bugs today — def values win — but
they will lie the day a knob is deleted from items.js)

- `heartSnob`: web fallbacks `itemNum(..., "value", 4)` at
  `index.html:12895,12929` vs def `value: 2` (TEXT "+2 coins" is correct).
- `heartDemolish`: fallback `coinPerPile` 7 (`index.html:13615`,
  `GameEngineBases.swift:96`; stale code comment "+7 coins" at
  `index.html:13605`) vs def 4 (TEXT "+4 coins" is correct).
- `linkHeavy`: fallbacks `value 5` / `hubValue 5` (`index.html:13750-13751`,
  `GameEngineBases.swift:642-644`) vs def 1/3 (TEXT "+1 … +3" is correct).
- `kamikaze`/`demolish`: `peekCount` fallback 3 vs kamikaze def 2
  (`index.html:13375,13593`).
- Dead knob comment: `items.js:456-457` documents a `selfDestruct` knob on
  `static` that no entry carries; the engine still reads `t.selfDestruct`
  (`index.html:27209-27212`) while a comment at `index.html:14194` says the
  knob was removed. Data-comment only; TEXT unaffected.

## 2. EMPTY / PLACEHOLDER descriptions

None. All 132 entries carry a non-empty `description` (verified by script:
"MISSING DESC: none"). The only near-placeholder is intentional:
`store.mysterySamePower` TEXT: "Purchase to reveal" — it is deliberately a
teaser (the concrete power is rolled at buy time, v6.51).

## 3. DUPLICATES

Exact duplicate TEXT (verified by script over all 132 entries — the only
exact collision):

- `rechargeSameShield` (sticker "Recharge Shield") and `rechargeSame` (base
  "Recharge Cell") share TEXT: "Bank a Same Charge (max 1)". Same words for
  two different classes (passive landing trigger vs. once-per-deal active) —
  consider differentiating ("When this card lands → …" vs "Once per deal: …").

Near-duplicates (not exact; listed so an edit pass can decide whether the
echoes are deliberate):

- `quickBury` "…bury 1 card under the pile" ≈ `clubSnob` suffix "…bury 1
  deck card under the pile" ≈ `clubRoots` "Bury 1 deck card under each pile
  with a ♣ top card" ≈ `linkBury` "Bury 1 card under every alive pile with a
  {suit} top card".
- Peek phrasing recurs across 9 items with 3 spellings: "Peek at the next
  deck card" (`revealNext`), "peek at the next deck card" (`suitSnob` suffix),
  "Peek at the next card" (`twinSpark`, `pillarScout`, `baseScout`,
  `queensEye`, `lastRites`, `samePeek` "Peek at the next upcoming card"),
  "Peek the next card" (`spadePeek`, `lonePeek`), "peek the next N cards"
  (`kamikaze`, `demolish`).
- `evenOut` "Redistribute all piles in this column to equal size" ≈
  `diamondDistribution` "…redistribute all piles in this column to equal
  size" (base active vs pillar on-♦-landing — same effect words).
- `shuffleColumn` "Shuffle every pile in this column" ≈ `royalCourt` "…shuffle
  the other piles in this column" ≈ `diamondSnob`/`linkShuffle` "shuffle every
  alive pile" / "Shuffle every alive pile".
- `linkRevive` "Revive the largest dead pile on the board" ≈ base `revive`
  "Phoenix" "Revive a random dead pile in this column with one fresh card…" —
  note one is LARGEST, the other RANDOM; the words "Revive a … dead pile"
  could be confused.
