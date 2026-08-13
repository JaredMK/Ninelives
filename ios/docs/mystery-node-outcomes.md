# ? Node interactions — the exhaustive script (build v6.29)

## The classes of ? node

There are exactly **three characters** a ? node can become. **The character rolls first** — `mystery.characterWeights`: **Old Joker 40%, Beheaded Queen 30%, Just a Two 30%** — then the action *within* that character rolls by the action weights, restricted to that character's pool:

1. **THE OLD JOKER** (40%) takes the node over with an OFFER (a conversation modal), rolled over only the offers whose preconditions hold. Two of his visits pre-empt the character roll entirely: an unpaid **marker** (20% roll per node while debt is open) and a pending **drink** (25% roll per node).
2. **THE BEHEADED QUEEN** (30%) delivers every *good* plain outcome (a reveal panel with her portrait and one spoken line) — including the store **Detour**.
3. **JUST A TWO** (30%) delivers every *bad* plain outcome the same way — plus the **Windfall** (more cards = deck bloat, its one "gift") and two conversation-style offers: **The Con** and **The Two's Game**.

*(The only presenter-less reveals left are the ones chained from the Old Joker's Two Doors, which run bare inside his frame.)*

## Shared UI (applies everywhere below)

- **No popup can be dismissed by tapping outside it.** Character modals leave only through a choice; reveal panels only through CONTINUE.
- **MAP** — a small chip in the panel's **top-right corner** (like a pause button, never one of the choices). It fades the popup so the whole map scrolls; a floating gold **◀ BACK TO THE JOKER** / **◀ BACK TO THE TWO** / **◀ BACK** button (bottom of screen) is the only live control; map travel stays locked. The offer is still on the table when you return.
- **Button colors:** GREEN = the headline accept (CTA) · GOLD = a paid/coin-flavored accept · RED = a dangerous accept · PLAIN (dark) = neutral / walk away. Sub-labels (the small text under a button) are listed with each button below as “↳”.
- **Item trades** draw the store's compare block: `YOURS` box (item art, name, registry description) → gold arrow → `HIS` / `HE PAYS` / `ON HIM` box (phosphor-rimmed).
- **The Old Joker's closing modal** (after any resolved offer): his portrait, one spoken closing line (quoted), the result line, and a single green **GO ON** button. Declining any offer closes with: *“He shuffles himself back into the dark.”* + *“He watches you go.”* Accepting closes with: *“He tips a corner of himself at you.”* + the result line — exceptions noted.

---

## CLASS 1 · THE OLD JOKER — 18 offers

*Modal layout: his card portrait (left) · THE OLD JOKER in gold · his line in quotes · the terms · [compare block if an item trade] · buttons.*

### 1 · Buyout — weight 12 · needs ≥1 equipped item *(only ever offers things you actually have equipped; ownership is re-checked at resolve)*
- **Line:** “Everything you carry has a number on it. Most folks never learn theirs.”
- **Terms:** “He'll buy **[A]** for **X**, or **[B]** for **Y**.” — one item only: “He'll buy [A] for X. That's the number.”
- **Compare:** one `YOURS → HE PAYS` row per item (coin art, “+X coins”, “into your purse”).
- **Buttons:** GOLD **SELL [B]** ↳ “+Y coins” · PLAIN **SELL [A]** ↳ “+X coins” · PLAIN **WALK AWAY**
- **Accept closing:** “[Item] is his now.”

### 2 · Swap — 10 · needs an equipped Pillar or Base *(only from your real loadout)*
- **Line:** “Trade you. Mine's older. Older is not the same as worse.”
- **Terms:** “He offers to take **[yours]** and leave **[his]** in its place.” *(his item is never a duplicate of something you already wear)*
- **Compare:** `YOURS → HIS`, both drawn in full.
- **Buttons:** GREEN **TRADE** · PLAIN **WALK AWAY**
- **Accept closing:** “[Yours] out, [his] in.”

### 3 · Purge — 8 · deck > 6 cards
- **Line:** “Three go in the fire. Something has to keep it lit.”
- **Terms:** “Purge 3 cards of your choosing, but 3 others are cursed with Leech.”
- **Item key:** Leech + its registry text (“Cursed. When this card lands → −3 coins”).
- **Buttons:** RED **PURGE 3** ↳ “3 others get cursed” · PLAIN **WALK AWAY**
- **Flow:** “Pick your three” / “Then he takes his due.” → **3 forced removal pickers** (banner “∅ Purge — Pick a card to permanently remove from your deck.”, no ✕) → a reveal shows the marked cards: title = the sticker's name, “N cards took his mark.” → closing modal.

### 4 · Ride — 7 · a shop reachable before this stage's boss
- **Line:** “I'm headed that way. What's between here and there won't miss you.”
- **Terms:** “5 coins for the lift. Ride to the next shop.”
- **Buttons:** GREEN **GET IN** ↳ “−5 coins” *(broke: button DEAD, ↳ “you have N — the fare is 5”)* · PLAIN **WALK AWAY**
- **Accept closing:** “N stops pass you by.” → he escorts your token up the map, then the shop opens.

### 5 · Cut — 12 · deck > 1
- **Line:** “One card leaves tonight. Only question is whose hand picks it.”
- **Terms:** “One card purged. Free if he picks it — 4 coins to pick it yourself.”
- **Buttons:** PLAIN **LET HIM PICK** ↳ “free” · GOLD **PICK IT YOURSELF** ↳ “4 coins” *(plain when broke)* · PLAIN **WALK AWAY**
- **Him picking:** closing — “[Card] never existed.”
- **You picking:** “Choose the one that leaves.” → forced removal picker → closing — “**[Card] purged.**”

### 6 · Marker — 8 · no marker already open
- **Line:** “Take it. Spend it. I'm patient — right up until I'm not.”
- **Terms:** “N coins now. He may come looking for it later, with interest.” *(the repay figure — 1.5×, 12–20 loaned — is deliberately never shown)*
- **Buttons:** GOLD **TAKE THE MARKER** ↳ “+N now · owed later” · PLAIN **WALK AWAY**
- **Accept closing:** “He'll want M back. Sometime.” → then 20% per ? node he **Collects** (offer 11).

### 7 · Blind Swap — 9 · a COMMON item equipped
- **Line:** “Don't look. Looking's how people talk themselves out of good things.”
- **Terms:** “One of your common items for something rarer. Neither is shown until it's done. He's looking at **[item]**.”
- **Compare:** `YOURS` (drawn) → `HIS` = a big gold **?** — “Something rarer”
- **Buttons:** GREEN **DON'T LOOK** · PLAIN **WALK AWAY**
- **Accept closing:** “[Yours] for [his].” *(the reveal happens here)*

### 8 · Two Doors — 12 · always available
- **Line:** “Two doors. I shuffled them myself, so don't ask me which.”
- **Terms:** “Two doors, both face down. One is kind. One is not.”
- **Buttons:** PLAIN **LEFT DOOR** · PLAIN **RIGHT DOOR** · PLAIN **WALK AWAY**
- **Flow:** “This one was kind.” / “This one was not.” → a **bare reveal panel** (no presenter — his doors, his frame): good = coins / cards / sticker / free removal · bad = toll / cursed sticker / ambush → closing modal.

### 9 · Insurance — 10 · Same shield EMPTY and ≥2 coins
- **Line:** “That shield of yours is empty. Empty things break first.”
- **Terms:** “2 coins and your Same shield is charged.”
- **Buttons:** GOLD **PAY 2** ↳ “charges the Same shield” · PLAIN **WALK AWAY**
- **Accept closing:** “The shield hums back to life.”

### 10 · Refund — 8 · needs ≥1 equipped item
- **Line:** “Sell it back. No shame in it. The deck remembers, you know.”
- **Terms:** “He's pointing at two of your things, and he pays well over what you did. Sell him one — or neither.”
- **Mechanics:** exactly **2 items rolled at random** (1 if you only have 1); each priced **2–3× its own shop price**, rolled per node.
- **Compare:** a `YOURS → HE PAYS` row per item.
- **Buttons:** GOLD **SELL [A]** ↳ “+N coins” · GOLD **SELL [B]** ↳ “+M coins” · PLAIN **WALK AWAY**
- **Accept closing:** “[Item] for N.”

### 11 · Collection — forced while a marker is open (20%/node)
- **Line:** “There you are. I did say I'd see you again.”
- **Terms:** “The marker is due: N coins. He takes what's there if it's short.”
- **Buttons:** RED **PAY UP** — **there is no walk away.**
- **Closing:** *“Debts settled. For now.”* + “He counts it twice and nods.” / short: “He takes what there is. Calls it even.”

### 12 · Free Shop — 8 · slotted item equipped, no comp already owed
- **Line:** “One of yours, and the next shop forgets how to charge you.”
- **Terms:** “Give him **[item]**. The next shop's whole shelf costs nothing.”
- **Compare:** `YOURS → ON HIM` (shop-stall art — “The next shop, comped / The whole shelf costs nothing until you refresh it.”).
- **Buttons:** GREEN **HAND IT OVER** ↳ “[item] · worth N” · PLAIN **WALK AWAY**
- **Accept closing:** “[Item] for a shop with no prices on it.”

### 13 · Purge Reset — 6 · the shop's removal ladder has climbed
- **Line:** “That slot's been bleeding you. I can have a word with it.”
- **Terms:** “The Purge slot halves, X down to Y — and every Purge after this one climbs faster.”
- **Buttons:** GOLD **HALVE IT** ↳ “X → Y · steeper after” · PLAIN **WALK AWAY**
- **Accept closing:** “Purge drops from X to Y — but it climbs faster now.”

### 14 · Eights — 6 · an Ace or 2 still in the deck
- **Line:** “Aces and deuces. All that distance, and for what? Come to the middle.”
- **Terms:** “Every Ace and 2 in your deck — N cards — becomes an 8.”
- **Buttons:** GREEN **COME TO THE MIDDLE** ↳ “N cards → 8” · PLAIN **WALK AWAY**
- **Accept closing:** “N cards flattened to 8.”

### 15 · Thirsty — 10 · no drink already pending
- **Line:** “I'm dry. Whatever you can spare — I'm not proud about the amount.”
- **Terms:** “Give him what you like. He has a long memory for both answers.” *(broke: “You have nothing to give. He'll remember being asked all the same.”)*
- **UI:** a **− / + coin stepper** over “you have N”. The commit button reads GOLD **GIVE N**, or PLAIN **GIVE HIM NOTHING** at zero. **No walk away** — zero *is* the refusal.
- **Paid closing:** *“Then you.”* + “N coins for his drink. He'll find you again.”
- **Stiffed closing:** *“Right. Nothing it is.”* + “You gave him nothing. He'll find you again.”

### 16 · The Drink, Returned — 25% per ? node while a drink is pending
- **Paid — line:** “You bought me a drink. I don't forget either kind of thing.” **Terms:** “He pays his debts in things, not coins.” **Button:** GREEN **TAKE THEM** → his coat opens as a **free store shelf** (items worth 2× what you gave — browse, take and place exactly like purchases at 0; DONE ends it; refreshing would end it too).
- **Stiffed — line:** “You had coins. I watched you keep them.” **Terms:** “He wants it out of your hide: a short, ugly deal.” **Button:** RED **FACE HIM** → an **18-card ambush deal** on 4 piles.
- No walk away either way.

### 17 · Duplicate — 9 · a normal (non-Joker) card owned
- **Line:** “Anything worth having is worth having twice. There's a cost to the second one.”
- **Terms:** “Copy any card you own, stickers and all. The copy carries a Leech and takes the place of another card you choose.”
- **Item key:** Leech + registry text.
- **Buttons:** GREEN **COPY A CARD** ↳ “the copy comes back marked” · PLAIN **WALK AWAY**
- **Flow:** picker 1 — “Copy a card / Pick the card he copies, stickers and all.” → picker 2 — “Replace with [card] / The copy of [card] carries a Leech. Pick the card it takes the place of.” (banner shows the copy WITH its mark) → closing modal.

### 18 · A Star for Your Flags — 7 · ≥1 Pillar equipped + joker-cap room
- **Line:** “All them flags you're flying. Give me the lot and I'll deal you a star.”
- **Terms:** “Every equipped Pillar comes down — all N — and a ★ Joker joins your deck.”
- **Compare:** ONE `YOURS → HIS` row: left names every Pillar (“All N Pillars”), right is the ★ Joker card — “Always a correct call, whichever way you guess.”
- **Buttons:** GREEN **TAKE THE STAR** ↳ “N Pillars come down” · PLAIN **WALK AWAY**
- **Accept closing:** “N Pillars down; a ★ Joker joins your deck.”

---

## CLASS 2 · THE BEHEADED QUEEN — 11 reveals (all good)

*Panel layout: her torn-card portrait · THE BEHEADED QUEEN in gold · her line in quotes · gold outcome title · [art, when there is something real to show] · outcome text · GREEN **CONTINUE** · corner MAP chip. Phosphor rim.*

| # | Title [weight] | Trigger / fold | Her line | Outcome text | Art | After CONTINUE |
|---|---|---|---|---|---|---|
| 1 | **Cache** [15] | always | “Take them. I stopped counting what I was owed a long time ago.” | “+N coins” | coin +N | node clears |
| 2 | **Imprint** [10] | placeable sticker exists, else → Cache | “A little shine. It never saved me — may it fit you better.” | “A [Sticker] sticker to place on a card” | sticker chip | **forced** apply-picker: “Tap a card to apply [Sticker] to it.” |
| 3 | **Purge** [8] | always | “Let one go. Kinder when it's your own choice. I would know.” | “Remove a card from the deck” | torn card | **forced** removal picker: “Pick a card to permanently remove from your deck.” (skipped silently on a 1-card deck) |
| 4 | **Cleanse** [7] | a stickered card exists, else → Cache | “Peel it off. Whatever they stuck to you, you don't have to keep.” | “Strip a sticker from a card” | torn card | **forced** strip picker: “Cleanse — Pick a card — one random sticker is stripped from it. The stripped sticker is destroyed.” |
| 5 | **Wild Card** [5] | joker-cap room, else → Cache | “He never took sides when it mattered. Maybe he'll take yours.” | “A ★ Joker joins your deck” | the ★ card | the card flies to your deck counter |
| 6 | **Fire Sale** [6] | always | “I told the shopkeep what a crown is worth. Everything's a coin till they restock.” | “At the next shop every item costs 1 coin — until you refresh the shelf” | — | armed for the next shop only |
| 7 | **Restock** [6] | always | “Make them set the shelf again. Tell them the Queen is paying.” | “The next shop's first REFRESH costs nothing” | — | armed; after use the ladder resumes at 6 |
| 8 | **Mulligan** [6] | always | “Take the hand back once, on me. Everyone deserves a second dealing.” | “Your next deal's first RESHUFFLE costs nothing” | — | armed; after use the ladder resumes at 5 |
| 9 | **Charged** [5] | shield EMPTY, else → Cache | “A shield. I'd have kept mine up, if I'd known which day to.” | “Your Same shield is charged, on her” | — | shield lit |
| 10 | **Doubled** [4] | coins > 0, else → Cache | “Whatever you've saved, I'll match it. It was all going spare anyway.” | “+N coins — your purse, matched” | coin +N | purse doubled |
| 11 | **Keepsake** [5] | always (Lammy's arrives sticker-free) | “I dressed this one myself. Give it a better life than mine.” | “[Card] — swap it in for a card of your choice” | the card, wearing its 2–3 stickers | swap picker: “Pick a card to replace with this one (the old card is removed; deck stays 52).” — **Skip** keeps it in the tray for later |
| 12 | **Detour** [5] | always | “The shopkeep still owes me a kindness. Go in — I told them you'd come.” | “The store opens on the spot — the node waits for you” | shop stall | the shop opens over the node; **DONE** in the shop clears it |

---

## CLASS 3 · JUST A TWO — 8 reveals + THE CON

*Same panel layout with its scowling two-of-spades portrait and red rim (Windfall keeps the good rim, delivered bitterly).*

| # | Title [weight] | Trigger / fold | Its line | Outcome text | Art | After CONTINUE |
|---|---|---|---|---|---|---|
| 1 | **Windfall** [12] | always | “More cards. Congratulations. A fat deck never saved anyone.” | “[Card] joins your deck” / “N cards join your deck” | the card faces | cards fly to the deck |
| 2 | **Toll** [12] | coins > 0, else → Cache | “Everyone takes from a two. Today a two takes from you.” | “−N coins” | coin −N | node clears |
| 3 | **Cursed** [14] | an eligible card exists | “You get stepped on your whole life, you start leaving marks.” | “[Leech / Trapdoor] afflicts your [card]” | the cursed chip | the curse stays on the card |
| 4 | **Ambush** [8] | always | “Nobody ever backs down from a two. Let's see how you do surrounded.” | “Survive an 18-card deal on 4 piles → +N coins” | 4 face-down piles (your card backs) | the ambush deal starts immediately |
| 5 | **Peeled** [6] | a stickered card exists, else → Toll | “Shiny little things. You didn't earn them either.” | “[Sticker] + [Sticker] torn off your [card]” — every sticker named | the stripped card | node clears |
| 6 | **Repossessed** [5] | an equipped Pillar/Base exists, else → Toll | “You'll do without. Twos always do.” | “[Item] is taken off column N” | the item's art | the item is gone — not pocketed, gone |
| 7 | **Markup** [6] | always | “I had a word with the shop. For once the prices aren't MY problem.” | “At the next shop every item costs DOUBLE” | — | armed for the next shop only |
| 8 | **Punctured** [5] | shield CHARGED, else → Toll | “A shield. Must be nice. Was nice.” | “Your charged Same shield is drained” | — | shield emptied |

### THE CON [4] — its one conversation offer · needs a ★ Joker held, else → Toll
*The Old Joker's modal layout, wearing the Two's card and name. Corner MAP chip; back button reads ◀ BACK TO THE TWO.*
- **Line:** “I know Mamma. Personally. I can take you to her. For every coin you've got, or one of them stars.”
- **Terms:** “Pay what it asks, and Just a Two says it will bring you to Mamma. It seems very sure of itself.”
- **Buttons:** RED **GIVE ALL YOUR COINS** ↳ “−N coins” *(DEAD at 0 coins)* · RED **GIVE A ★ JOKER** ↳ “one leaves your deck” · PLAIN **WALK AWAY**
- **If you pay (either):** reveal — **The Long Walk** — “[N coins / Your ★ Joker], gone. It walked you in one big circle and wandered off. Mamma never came.” Its header line: “You believed that? A two doesn't know ANYBODY.” **Nothing arrives. It was lying.**

### THE TWO'S GAME [5] — its second conversation offer · needs the Same shield CHARGED, else → Toll
*Same modal layout as The Con. Corner MAP chip; back button reads ◀ BACK TO THE TWO. There is no walk-away — it demands the call.*
- **Line:** “I'm thinking of a card. Higher or lower than an 8? Twos always know. Let's see if you do.”
- **Terms:** “One call against its hidden card. Win and you get nothing. Lose and your Same shield is drained.”
- **Buttons:** PLAIN **HIGHER** · PLAIN **LOWER** · PLAIN **SAME**
- **The card:** rolled seeded per node (any suit, any rank in the deck's range); the pivot rank is a knob (`mystery.twoGame.pivot`, 8).
- **If you win:** reveal — **Nothing** — “You called it. You win nothing. It seems pleased anyway.” The hidden card is shown. Nothing changes.
- **If you lose:** reveal — **Punctured** — “Wrong. Your Same shield is drained.” The hidden card is shown; the shield empties.

---

*(The bare Two-Doors chained reveals are noted under Old Joker offer 8 — they are the only panels with no character header.)*
