/* ============================================================================
   NINELIVES ITEM DATA — the single hand-editable source for EVERY shop item.

   Edit this file to tune the game: prices, rarities, store weights, the
   store shelf shape (slots / type cap / reroll cost), the pack-card
   sticker odds, descriptions, and every effect's numeric knobs live
   HERE. The game logic
   (in index.html) is keyed by item `id` and reads all of its numbers from
   this file — tweaking a value never requires touching logic code.

   Shape of an entry (shared by every group):
     id           stable key — NEVER change it (saves, offers and tests bind
                  to it); rename the player-facing `label` instead
     label        the player-facing name
     icon         emoji fallback; the game bakes its own SVG glyph over this
                  where one exists (ELEM_GLYPH in index.html)
     kind/effect  which engine hook runs the item — changing these changes
                  BEHAVIOR, not tuning; leave them alone
     tier         "common" | "uncommon" | "rare" — how often the store OFFERS
                  it (see store.tierWeights below); independent of price
     weight       OPTIONAL store-offer weight override; when set it replaces
                  the tier weight for this one item
     suits        OPTIONAL (stickers only): the suit symbols this sticker may
                  be applied to, e.g. suits: ["♥"] or suits: ["♥","♦"]. A
                  sticker carrying the field only ever attaches to cards of
                  those suits (matched against the card's printed suit at
                  apply time — pickers grey out other cards, and effects that
                  apply stickers pick only eligible targets). Omit the field
                  for an any-suit sticker. Jokers and Removal cards can NEVER
                  receive stickers from any source, regardless of this field.
     price        fixed store price in coins (no per-purchase escalation)
     description  the store/help popup text — the single source of truth
                  (the game never hardcodes effect text)
     …tunables    any other numeric field is an effect knob (value, step,
                  threshold, digCount, peelChance, …) — safe to hand-edit
     unlock       OPTIONAL item-unlock gate: { type, stat, count }. ABSENT = a
                  starting item, always available — the ship state: no entry
                  carries this field, so every roll pool is identical to the
                  pre-feature game. When set, the item stays out of every roll
                  pool (sticker grants, store classes, sticker packs, Lammy's
                  pre-equip) until the LIFETIME counter `stat` (the Stats
                  record, ninelives.stats.v1) reaches `count`. `type` is
                  documentary — "milestone" (progression counters) or
                  "behavior" (playstyle counters); both gate identically and
                  it only flavors the hint copy. `stat` is one of these 15:
                    dealsSurvived      runsPlayed        runsWon
                    bossesBeaten       endlessStagesReached
                    coinsEarnedLifetime
                    cardsBuried        samesCalled       correctSames
                    jokersPlayed       stickersApplied   pillarsPlaced
                    basesPlaced        removalsUsed      pilesLost
                  `count` is a positive finite number. A malformed gate fails
                  loudly at load (the validator names the item id).
                  Example (keep it COMMENTED — no live unlock field ships
                  without the full feature pass):
   // { id: "example", label: "…", tier: "rare", price: 20, description: "…",
   //   unlock: { type: "behavior", stat: "cardsBuried", count: 15 } },

   Malformed entries do NOT silently disappear: the game validates this file
   on load and fails loudly in the console with the offending item id.
============================================================================ */
"use strict";

const NINELIVES_ITEMS = {

  /* --------------------------------------------------------------------
     STORE CONFIG — shelf shape, offer weighting + the permanent Removal
     slot.
     slots/typeCap/reroll: the shelf holds `slots` slots per visit; at most
     `typeCap` slots of one item TYPE (card packs and sticker packs count
     as separate types; the permanent Removal slot, when on, occupies the
     last slot and the cap applies across just the rolled ones). A reroll
     replaces ALL slots for reroll.baseCost, climbing reroll.step per
     reroll within a visit.
     classWeights: CLASS-FIRST roll — each of the 5 rolled slots picks its
     item CLASS by these relative weights, THEN an item within that class
     (rarity-weighted by tierWeights; an item's own `weight` field, when
     present, overrides its tier's). "card" is a single playing card slot
     (see store.card below).
  -------------------------------------------------------------------- */
  store: {
    slots: 6,
    typeCap: 3,
    reroll: { baseCost: 3, step: 1 },
    classWeights: { sticker: 40, pillar: 20, base: 20, pack: 8, card: 8, samepower: 4 },
    tierWeights: { common: 100, uncommon: 50, rare: 20 },
    // The INDIVIDUAL-CARD slot: one playing card, rolled with the same
    // odds it would have inside a card pack (suits in play, the same
    // chance of carrying stickers, Mr. Smith's rates where applicable).
    // Removal cards never appear here. A Joker may roll in at the plain
    // any-card rate (1/53) but costs jokerPrice instead of price; the
    // difficulty tier's joker cap applies (none on Legendary).
    card: {
      label: "Card", icon: "🂠", price: 8, jokerPrice: 50,
      description: "A single card. Swap it into your deck, replacing a card of your choice.",
    },
    // The debug-toggleable permanent 6th store slot: fixed price, never
    // depletes, each purchase runs the choose-a-card-to-remove flow.
    removal: {
      id: "removal", label: "Removal", icon: "∅", price: 10,
      description: "Permanently remove a card of your choice from your deck. Repeatable — the slot never empties.",
    },
  },

  /* --------------------------------------------------------------------
     STICKERS — card-bound modifiers ("Imprints"). A card may hold any
     number of stickers, duplicates included. `rankDelta`, `tributeCount`,
     `coinCost`, `value`, `step`, `per`, `max`, `peelChance`, `count` are
     effect knobs.
     SUIT-TIMING PRICING convention: a ♣ item costs its ♦/♥ twin's price −1;
     a ♠ item costs −2 (floor 1).
  -------------------------------------------------------------------- */
  stickers: [
    { id: "rankUp",     label: "+1 Rank",     icon: "➕", kind: "rank",     rankDelta: 1,  tier: "common",   price: 1,
      description: "+1 card rank (stops at Ace)"},
    { id: "rankDown",   label: "−1 Rank",     icon: "➖", kind: "rank",     rankDelta: -1, tier: "common",   price: 1,
      description: "-1 card rank (stops at 2)" },
    { id: "rankUp2",    label: "+2 Rank",     icon: "⏫", kind: "rank",     rankDelta: 2,  tier: "uncommon", price: 2,
      description: "+2 card rank (stops at Ace)." },
    { id: "rankDown2",  label: "−2 Rank",     icon: "⏬", kind: "rank",     rankDelta: -2, tier: "uncommon", price: 2,
      description: "-2 card rank (stops at 2)" },
    { id: "randomFixedValue", label: "Random Rank", icon: "🎰", kind: "behavior", behavior: "randomFixedValue", tier: "uncommon", price: 1,
      description: "Set to random rank" },
    { id: "changeSuitRandom", label: "Random Suit", icon: "🎲", kind: "behavior", behavior: "changeSuitRandom", tier: "common", price: 1,
      description: "Change to a random suit ♠♣♥♦" },
    { id: "changeSuitSpade",  label: "Change to ♠", icon: "♠️", kind: "behavior", behavior: "changeSuitTo", suit: "♠", tier: "common", price: 1,
      description: "Change suit to ♠" },
    { id: "changeSuitHeart",  label: "Change to ♥", icon: "♥️", kind: "behavior", behavior: "changeSuitTo", suit: "♥", tier: "common", price: 1,
      description: "Change suit to ♥" },
    { id: "changeSuitDiamond", label: "Change to ♦", icon: "♦️", kind: "behavior", behavior: "changeSuitTo", suit: "♦", tier: "common", price: 1,
      description: "Change suit to ♦" },
    { id: "changeSuitClub",   label: "Change to ♣", icon: "♣️", kind: "behavior", behavior: "changeSuitTo", suit: "♣", tier: "common", price: 1,
      description: "Change suit to ♣" },
    { id: "tieSafe",    label: "Same-Safe",   icon: "🛡️", kind: "behavior", behavior: "tieSafe", tier: "common", price: 4,
      description: "Safe if this card lands on a card of the same rank, or a card of the same rank lands on this card" },
    { id: "suitImmunity", label: "Spade Guard", icon: "♠️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♠", tier: "uncommon", price: 6,
      description: "Safe if this card lands on a ♠, or a ♠ lands on this card" },
    { id: "heartGuard", label: "Heart Guard", icon: "♥️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♥", tier: "uncommon", price: 6,
      description: "Safe if this card lands on a ♥, or a ♥ lands on this card" },
    { id: "diamondGuard", label: "Diamond Guard", icon: "♦️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♦", tier: "uncommon", price: 3,
      description: "Safe if this card lands on a ♦, or a ♦ lands on this card" },
    { id: "clubGuard",  label: "Club Guard",  icon: "♣️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♣", tier: "uncommon", price: 3,
      description: "Safe if this card lands on a ♣, or a ♣ lands on this card" },
    // value = coins per Extra Coin UNIT (units = stickers on the alive top card
    // × cards in that pile; Economy multiplies units by this value).
    { id: "extraCoin",  label: "Payout",      icon: "💰", kind: "behavior", behavior: "extraCoin", value: 1, tier: "uncommon", price: 2,
      description: "At deal end → earn coins equal to pile size if this card tops its pile", suits: ["♥"] },
    { id: "gainCoin",   label: "Bonus Coin",  icon: "🍀", kind: "behavior", behavior: "gainCoin", value: 1, tier: "common", price: 2,
      description: "When this card lands → +1 coin", suits: ["♥"] },
    { id: "anchor",     label: "Anchor",      icon: "⚓", kind: "behavior", behavior: "anchor", tier: "common", price: 3,
      description: "At deal end → exclude this pile from the smallest-pile score if this card tops its pile", suits: ["♦"] },
    { id: "oneTribute", label: "Bury 1",      icon: "🪦", kind: "behavior", behavior: "tribute", tributeCount: 1, tier: "rare", price: 10,
      description: "When this card lands → bury 1 deck card under the pile", suits: ["♣"] },
    { id: "twoTribute", label: "Bury 2",      icon: "⚰️", kind: "behavior", behavior: "tribute", tributeCount: 2, coinCost: 7, tier: "rare", price: 16,
      description: "When this card lands → bury 2 deck cards under the pile. Costs 7 coins", suits: ["♣"]  },
    { id: "deathBounty", label: "Last Coin",  icon: "💀", kind: "behavior", behavior: "deathBounty", value: 5, tier: "common", price: 3,
      description: "When this card lands → +5 coins if it kills a pile", suits: ["♥"] },
    // value = extra pile-size weight per Heavy sticker on a card.
    { id: "heavy",      label: "Heavy",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 1, tier: "common", price: 2,
      description: "When placed → +1 toward pile size",suits: ["♦"]  },
     { id: "massive",      label: "Massive",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 2, tier: "uncommon", price: 4,
      description: "When placed → +2 toward pile size",suits: ["♦"]  },
    { id: "collector",  label: "Collector",   icon: "🧲", kind: "behavior", behavior: "collector", value: 2, tier: "uncommon", price: 2,
      description: "When this card lands → +2 coins per other sticker on this card", suits: ["♥"] },
    // step = coins the payout grows per correct placement (pays 0 on the first).
    { id: "compound",   label: "Compound",    icon: "📈", kind: "behavior", behavior: "compound", step: 1, tier: "rare", price: 2,
      description: "When this card lands → +X coins. X starts at 0, grows by 1 per correct placement", suits: ["♥"] },
    { id: "revealNext", label: "Scout",       icon: "👁️", kind: "behavior", behavior: "revealNext", tier: "rare", price: 12,
      description: "When this card lands → peek at the next deck card", suits: ["♠"]  },
    { id: "wildSuit",   label: "Wild Suit",   icon: "♠♥♦♣", kind: "behavior", behavior: "wildSuit", tier: "common", price: 2,
      description: "Counts as every suit" },
    { id: "shuffle",    label: "Shuffle",     icon: "🔀", kind: "behavior", behavior: "shuffle", tier: "uncommon", price: 2,
      description: "When this card lands → optionally shuffle the pile", suits: ["♦"]  },
    // count = buried cards moved to the smallest pile per accepted Donate.
    { id: "donate",     label: "Donate",      icon: "🤝", kind: "behavior", behavior: "donate", count: 1, tier: "common", price: 1,
      description: "When this card lands → move 1 buried card from this pile to the smallest pile", suits: ["♦"]  },
    // peelChance = probability (0–1) the sticker destroys itself after burying.
    { id: "quickBury",  label: "Quick Bury",  icon: "⚡", kind: "behavior", behavior: "quickBury", tier: "uncommon", price: 7,
      description: "When this card lands → bury 1 deck card under the pile", suits: ["♣"]  },
    { id: "twinSpark",  label: "Twin Spark",  icon: "✨", kind: "behavior", behavior: "twinSpark", tier: "uncommon", price: 5,
      description: "When this card lands → peek at the next card if another pile's top card matches this rank", suits: ["♠"]  },
    // max = the top of the random 0–max coin roll.
    { id: "looseChange", label: "Loose Change", icon: "🪙", kind: "behavior", behavior: "looseChange", max: 3, tier: "uncommon", price: 4,
      description: "When this card lands → +0–3 coins (random)", suits: ["♥"] },
    // step = how much X (cards buried) grows per correct placement.
    { id: "snowball",   label: "Snowball Bury", icon: "☃️", kind: "behavior", behavior: "snowball", step: 1, tier: "rare", price: 20,
      description: "When this card lands → bury X cards. X starts at 0, grows by 1 per correct placement, resets on a wrong guess", suits: ["♣"] },
    // per = deck cards per +1 coin (floor(deck remaining ÷ per)).
    { id: "deepPockets", label: "Deep Pockets", icon: "👛", kind: "behavior", behavior: "deepPockets", per: 10, tier: "uncommon", price: 2,
      description: "When this card lands → +1 coin per 10 cards left in the deck", suits: ["♥"]},
    { id: "pillarScout", label: "Pillar Scout", icon: "🔭", kind: "behavior", behavior: "pillarScout", tier: "uncommon", price: 3,
      description: "When this card lands → peek at the next card if this column has no pillar", suits: ["♠"]  },
    { id: "baseScout",  label: "Base Scout",  icon: "🔎", kind: "behavior", behavior: "baseScout", tier: "uncommon", price: 3,
      description: "When this card lands → peek at the next card if this column has no base", suits: ["♠"]  },
    // ---- the Snob family: each fires when a matching-suit card LANDS ON this card ----
    { id: "suitSnob",   label: "Spade Snob",  icon: "🧐", kind: "behavior", behavior: "suitSnob", tier: "uncommon", price: 3,
      description: "When a ♠ lands on this card → peek at the next deck card"},
    // value = coins paid per Heart Snob on the landing card.
    { id: "heartSnob",  label: "Heart Snob",  icon: "💞", kind: "behavior", behavior: "heartSnob", value: 4, tier: "uncommon", price: 2,
      description: "When a ♥ lands on this card → +4 coins"},
    { id: "diamondSnob", label: "Diamond Snob", icon: "💎", kind: "behavior", behavior: "diamondSnob", tier: "uncommon", price: 5,
      description: "When a ♦ lands on this card → shuffle all piles"},
    // digCount = deck cards buried under the pile per Club Snob.
    { id: "clubSnob",   label: "Club Snob",   icon: "🍀", kind: "behavior", behavior: "clubSnob", digCount: 1, tier: "uncommon", price: 10,
      description: "When a ♣ lands on this card → bury 1 deck card under the pile"},
    // ---- the suit-SYNERGY family: each fires when THIS card lands, scaling
    // by the number of OTHER piles topped by its suit (the landing pile
    // itself never counts). ----
    // value = coins per other ♥-topped pile.
    { id: "heartChoir", label: "Heart Choir", icon: "💕", kind: "behavior", behavior: "heartChoir", value: 1, tier: "uncommon", price: 6,
      description: "When this card lands → +1 coin per other pile with a ♥ top card", suits: ["♥"] },
    { id: "diamondRipple", label: "Diamond Ripple", icon: "🌊", kind: "behavior", behavior: "diamondRipple", tier: "uncommon", price: 3,
      description: "When this card lands → shuffle every other pile with a ♦ top card", suits: ["♦"] },
    // digCount = deck cards buried under THIS pile per other ♣-topped pile.
    { id: "clubRoots", label: "Club Roots", icon: "🌱", kind: "behavior", behavior: "clubRoots", digCount: 1, tier: "rare", price: 15,
      description: "When this card lands → bury 1 deck card under each pile with a ♣ top card", suits: ["♣"] },
    { id: "spadeWhispers", label: "Spade Whispers", icon: "🌬️", kind: "behavior", behavior: "spadeWhispers", tier: "rare", price: 15,
      description: "When this card lands → the next X cards show a hint (higher/lower/same), where X = other piles with a ♠ top card", suits: ["♠"] },
    // step = coins X grows per correct placement (resets to 0 on a wrong one).
    { id: "tell",       label: "Tell",        icon: "🔮", kind: "behavior", behavior: "tell", tier: "uncommon", price: 7,
      description: "When this card lands → shows if the next deck card is higher, lower, or same", suits: ["♠"] },
    // ---- Same-charge / Same-power stickers (fire on correct placement) ----
    { id: "rechargeSameShield", label: "Recharge Shield", icon: "🛡️", kind: "behavior", behavior: "rechargeSameShield", tier: "rare", price: 15,
      description: "When this card lands correctly → bank a Same Charge (max 1)" },
    { id: "activateSamePower", label: "Tap Power", icon: "🔗", kind: "behavior", behavior: "activateSamePower", tier: "rare", price: 12,
      description: "When this card lands correctly → fire your equipped Same-Power" },
    // ---- CURSED stickers (mystery "?" node events ONLY) ---------------------
    // cursed: true keeps a sticker OUT of every normal grant pool (store offers,
    // sticker packs, pack-card generation, Mr. Smith's grants, Wild Sticker) —
    // only a mystery event applies one. price: 0 (never sold). value = coins
    // LOST each time the carrying card lands on a pile (behavior "tributeCoin").
    { id: "leech",      label: "Leech",       icon: "🪱", kind: "behavior", behavior: "tributeCoin", value: 1, tier: "common", price: 0, cursed: true,
      description: "Cursed — when this card lands → −1 coin" },
    { id: "leech2",     label: "Leech Swarm", icon: "🦟", kind: "behavior", behavior: "tributeCoin", value: 2, tier: "common", price: 0, cursed: true,
      description: "Cursed — when this card lands → −2 coins" },
  ],

  /* --------------------------------------------------------------------
     PILLARS — COLUMN modifiers bound to the TOP of a board column; their
     effect applies to every pile in that column, passively, all run.
     `value` is the coin/size coefficient; `threshold`/`trigger`/`digCount`/
     `minStickers`/`chance`/`selfDestruct` are effect knobs.
  -------------------------------------------------------------------- */
  pillars: [
    // +value per correct guess placing a matching-suit card in this column.
    { id: "heartBounty", label: "Heart Bonus", icon: "♥️",
      kind: "scoring", effect: "suitBounty", suit: "♥", value: 1, tier: "uncommon", price: 9,
      description: "When a ♥ lands in this column → +1 coin" },
    { id: "columnTieSafe", label: "Column Tie-Safe", icon: "🛡️",
      kind: "guess", effect: "columnTieSafe", tier: "rare", price: 12,
      description: "Every pile in this column survives a tie" },
    { id: "columnGuardian", label: "Guardian", icon: "🏛️",
      kind: "scoring", effect: "columnAllAlive", value: 7, tier: "uncommon", price: 7,
      description: "At deal end → +7 coins if every pile in this column survived" },
    // digCount = deck cards buried per qualifying (sticker-free ♣) landing.
    { id: "clubTribute", label: "8 Bury", icon: "8️⃣",
      kind: "composition", effect: "clubTribute", digCount: 1, tier: "rare", price: 25,
      description: "When a ♣ with no stickers lands correctly in this column → bury 1 deck card under that pile" },
    { id: "allHeartsCoin", label: "All Hearts", icon: "💗",
      kind: "scoring", effect: "allSuitTop", suit: "♥", value: 8, tier: "common", price: 8,
      description: "At deal end → +8 coins if every surviving pile in this column has a ♥ top card" },
    // value = coins per alive ♥-topped pile in this column at end of deal.
    { id: "envy", label: "Envy", icon: "💚",
      kind: "scoring", effect: "heartPiles", value: 4, tier: "common", price: 8,
      description: "At deal end → +4 coins per pile in this column with a ♥ top card" },
    // threshold = the in-column streak step the bonus starts at (+1 size per
    // step from there on; resets on a wrong guess or any other-column guess).
    { id: "streakBank", label: "Streak Size", icon: "🏦",
      kind: "modifier", effect: "streakSize", threshold: 3, tier: "rare", price: 8,
      description: "From the 3rd consecutive correct guess in this column → +1 pile size per guess. Resets on a wrong guess or any guess in another column" },
    // threshold = the streak step burials start at; digCount = cards buried
    // per correct in-column guess from that step onward (flat, no escalation).
    { id: "streakTribute", label: "Streak Bury", icon: "🔥",
      kind: "composition", effect: "streakTribute", threshold: 4, digCount: 1, tier: "rare", price: 20,
      description: "From the 4th consecutive correct guess in this column → bury 1 deck card per guess. Resets on a wrong guess or any guess in another column" },
    { id: "secondWind", label: "Second Wind", icon: "🌬️",
      kind: "guess", effect: "secondWind", tier: "rare", price: 12,
      description: "The first pile to die in this column is saved — but all its buried cards return to the deck" },
    { id: "greedy", label: "Greedy", icon: "🤑",
      kind: "scoring", effect: "greedy", value: 20, tier: "rare", price: 10,
      description: "At deal end → +20 coins if every pile in this column survived and no other pillar is on the board" },
    // value = coins per Fibonacci-rank (A/2/3/5/8) card drawn into the column.
    { id: "fibonacci", label: "Fibonacci", icon: "🌀",
      kind: "live", effect: "fibonacci", value: 1, tier: "rare", price: 8,
      description: "When a Fibonacci-rank card (A/2/3/5/8) lands correctly into this column → +1 coin" },
    { id: "highestEven", label: "Highest Heart", icon: "💗",
      kind: "scoring", effect: "highestHeart", tier: "rare", price: 15,
      description: "At deal end → earn coins equal to the highest numbered ♥ top card in this column (2–10 face value, Ace pays 1, royals pay 0)" },
    // minStickers = stickers a landing ♣ must carry; digCount = cards buried.
    { id: "denseBury", label: "Dense Bury", icon: "🧊",
      kind: "composition", effect: "denseBury", minStickers: 2, digCount: 1, tier: "rare", price: 20,
      description: "When a ♣ with 2+ stickers lands correctly in this column → bury 1 deck card under that pile" },
    // trigger = the pile size (cards) that arms the one-shot revive offer.
    { id: "revive", label: "Revive", icon: "♻️",
      kind: "guess", effect: "revive", trigger: 10, tier: "rare", price: 25,
      description: "When a pile in this column reaches 10 cards → revive one dead pile on the board" },
    // ---- expansion Pillars ------------------------------------------------
    { id: "insurance", label: "Insurance", icon: "🛟",
      kind: "scoring", effect: "insurance", value: 20, tier: "rare", price: 8,
      description: "At deal end → +20 coins if only one pile is alive board-wide and it's in this column" },
    { id: "ditto", label: "Ditto", icon: "🪞",
      kind: "meta", effect: "ditto", tier: "rare", price: 9,
      description: "Mirrors the center column's pillar" },
    // value = extra pile size per ♦ card (top or buried) in the column.
    { id: "stickerCount", label: "Massive Diamond", icon: "🏷️",
      kind: "modifier", effect: "heavyDiamond", value: 2, tier: "uncommon", price: 7,
      description: "♦ cards in this column count as +2 toward pile size" },
    // value = coins per prime-rank (2/3/5/7) card landing correctly here.
    { id: "prime", label: "Prime", icon: "🔢",
      kind: "live", effect: "prime", value: 1, tier: "rare", price: 6,
      description: "When a prime-rank card (2/3/5/7) lands correctly in this column → +1 coin" },
    { id: "queensEye", label: "Queen's Eye", icon: "👁️",
      kind: "live", effect: "queensEye", tier: "uncommon", price: 8,
      description: "When a royal ♠ (J/Q/K) lands correctly in this column → peek at the next card" },
    { id: "royalCourt", label: "Shuffler", icon: "👑",
      kind: "guess", effect: "shuffler", tier: "uncommon", price: 5,
      description: "When a ♦ lands in this column → shuffle the other piles in this column" },
    // value = coins per buried card in the largest ♥-topped alive pile.
    { id: "excavator", label: "Excavator", icon: "⛏️",
      kind: "scoring", effect: "excavator", value: 2, tier: "uncommon", price: 6,
      description: "At deal end → +2 coins per buried card in this column's largest pile with a ♥ top card" },
    // chance = probability (0–1) the flip pays `value` (needs a ♥ top here).
    { id: "gambler", label: "Gambler", icon: "🎲",
      kind: "scoring", effect: "gambler", value: 10, chance: 0.5, tier: "uncommon", price: 10,
      description: "At deal end → 50/50: +10 coins or nothing (requires a ♥ top card in this column)" },
    { id: "lastRites", label: "Last Rites", icon: "🕯️",
      kind: "live", effect: "lastRites", tier: "rare", price: 25,
      description: "When a pile in this column dies → peek at the next card" },
    // selfDestruct = probability (0–1) the Pillar destroys itself each deal end.
    // chance = probability the ♠ landing actually fires the peek.
    { id: "static", label: "Static", icon: "🔌",
      kind: "live", effect: "static", chance: 0.5, tier: "rare", price: 6,
      description: "When a ♠ lands in this column → 50% chance to peek at the next card" },
    { id: "wildAces", label: "Wild Aces", icon: "🃏",
      kind: "guess", effect: "wildAces", tier: "rare", price: 25,
      description: "Aces count as high or low when landing in this column" },
    { id: "diamondAnchor", label: "Diamond Anchor", icon: "⚓",
      kind: "modifier", effect: "diamondAnchor", tier: "rare", price: 12,
      description: "At deal end → exclude any pile in this column with a ♦ top card from the smallest-pile score" },
    { id: "diamondDistribution", label: "Diamond Distribution", icon: "⚖️",
      kind: "guess", effect: "diamondDistribution", tier: "uncommon", price: 6,
      description: "When a ♦ lands in this column → redistribute all piles in this column to equal size" },
  ],

  /* --------------------------------------------------------------------
     BASES — column artifacts bound to the BOTTOM of a column. ACTIVE,
     once-per-deal powers: they charge each deal, fire once when tapped,
     and stay spent until the next deal. `target: "pile"|"pillar"` means
     the player picks a target. `digCount`/`peekCount`/`coinPerPile`/
     `coinPerCard`/`buryPerSticker`/`reward` are effect knobs.
  -------------------------------------------------------------------- */
  bases: [
    // peekCount = upcoming cards peeked after the sacrifice.
    { id: "kamikaze", label: "Kamikaze", icon: "💥",
      kind: "active", effect: "kamikaze", peekCount: 3, tier: "rare", price: 15,
      description: "Kill a random ♠-topped pile in this column, then peek the next 3 cards" },
    { id: "spadePeek", label: "Spade Peeker", icon: "🔦",
      kind: "active", effect: "spadePeek", tier: "rare", price: 15,
      description: "Peek the next X cards, where X = piles in this column with a ♠ top card" },
    { id: "shuffleColumn", label: "Upheaval", icon: "🌀",
      kind: "active", effect: "shuffleColumn", tier: "common", price: 9,
      description: "Shuffle every pile in this column" },
    { id: "revive", label: "Phoenix", icon: "🔥",
      kind: "active", effect: "reviveBase", tier: "uncommon", price: 14,
      description: "Revive a random dead pile in this column with one fresh card (buried cards return to the deck)" },
    { id: "randomSticker", label: "Wild Sticker", icon: "🎲",
      kind: "active", effect: "randomSticker", tier: "uncommon", price: 5,
      description: "Apply a random sticker to a random top card in this column" },
    { id: "evenOut", label: "Ballast", icon: "🪨",
      kind: "active", effect: "evenOut", tier: "common", price: 9,
      description: "Redistribute all piles in this column to equal size" },
    { id: "setValue", label: "Cast", icon: "🗿",
      kind: "active", effect: "setValue", tier: "rare", price: 12,
      description: "Permanently set every top card's rank in this column to the bottom pile's rank" },
    { id: "setSuit", label: "Suit Setter", icon: "🎨",
      kind: "active", effect: "setSuit", tier: "rare", price: 18,
      description: "Permanently set every top card's suit in this column to the bottom pile's suit" },
    // buryPerSticker = deck cards buried per sticker peeled off the pile card.
    { id: "stickerHarvest", label: "Sticker Harvest", icon: "🌾",
      kind: "active", effect: "stickerHarvest", target: "pile", buryPerSticker: 2, tier: "uncommon", price: 11,
      description: "Choose a pile → bury 2 deck cards per sticker on its top card, then peel all those stickers" },
    { id: "refreshBases", label: "Reactor", icon: "⚛️",
      kind: "active", effect: "refreshBases", tier: "rare", price: 17,
      description: "Recharge your other two bases (never another Reactor)" },
    // ---- expansion Bases --------------------------------------------------
    // digCount = cards buried under each matching-suit-topped pile.
    { id: "clubDig", label: "Club Dig", icon: "♣️",
      kind: "active", effect: "suitDig", suit: "♣", digCount: 1, tier: "rare", price: 15,
      description: "Bury 1 deck card under each ♣-topped pile in this column" },
    // peekCount = upcoming cards peeked after the demolition.
    { id: "demolish", label: "Demolish", icon: "🔨",
      kind: "active", effect: "demolish", target: "pillar", peekCount: 2, tier: "uncommon", price: 25,
      description: "Choose a pillar → destroy it permanently, then peek the next 2 cards" },
    // coinPerPile = coins gained per ♥-topped pile destroyed.
    { id: "heartDemolish", label: "Heart Demolish", icon: "💔",
      kind: "active", effect: "heartDemolish", coinPerPile: 7, tier: "uncommon", price: 10,
      description: "Destroy every ♥-topped pile in this column. +7 coins per pile destroyed" },
    // coinPerCard = coins gained per ♥ card counted in the column.
    { id: "tax", label: "Heart Tax", icon: "🧾",
      kind: "active", effect: "tax", suit: "♥", coinPerCard: 1, tier: "uncommon", price: 9,
      description: "+1 coin per ♥ card in this column (top + buried, dead piles excluded)" },
    // ---- Same-charge / Same-power bases (activated, once per deal) ----
    { id: "rechargeSame", label: "Recharge Cell", icon: "🔋",
      kind: "active", effect: "rechargeSameShield", tier: "rare", price: 25,
      description: "Bank a Same Charge (max 1)" },
    { id: "activateSame", label: "Power Surge", icon: "⚡",
      kind: "active", effect: "activateSamePower", tier: "rare", price: 20,
      description: "Fire your Same-Power on a random pile in this column" },
  ],

  /* --------------------------------------------------------------------
     SAME-POWERS — the artifact class a correct Same triggers. Exactly ONE
     is equipped at a time; every power acts on the piles DIRECTLY linked
     (via the synapse network) to the pile the Same was called on.
     `value` is the per-link coefficient (cards buried / coins / size).
  -------------------------------------------------------------------- */
  samePowers: [
    // value = cards buried under EACH directly-linked alive pile.
    { id: "linkBury", label: "Burrow", icon: "🦫",
      effect: "linkBury", value: 1, tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Bury 1 card under each pile directly linked to the pile you called Same on" },
    { id: "linkRevive", label: "Rekindle", icon: "🌱",
      effect: "linkRevive", tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Revive one dead pile directly linked to the pile you called Same on" },
    // value = coins per directly-linked alive pile.
    { id: "linkCoins", label: "Dividend", icon: "💰",
      effect: "linkCoins", value: 5, tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Gain 5 coins for each pile directly linked to the pile you called Same on" },
    { id: "linkShuffle", label: "Link Shuffler", icon: "🔀",
      effect: "linkShuffle", tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Shuffle all piles directly linked to the pile you called Same on" },
    { id: "samePeek", label: "Same Peeker", icon: "👁️",
      effect: "samePeek", tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Peek at the next upcoming card" },
    // value = pile size added to each directly-linked pile; hubValue = pile
    // size added to the CALLED pile itself (both last the deal).
    { id: "linkHeavy", label: "Same Heavy", icon: "🧱",
      effect: "linkHeavy", value: 5, hubValue: 5, tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Add +5 pile size to the pile you called Same on and to each pile directly linked to it" },
  ],

  /* --------------------------------------------------------------------
     PACK-CARD STICKER ODDS — how many stickers one freshly granted card
     carries. [maxRoll, stickerCount] pairs, checked IN ORDER against a
     uniform 0..1 roll (a roll that passes every maxRoll gets 0 stickers);
     maxRoll must strictly ascend. ONE rule for every roll site: store
     card packs, the store's individual-card slot (genNormalCard) and
     Mr. Smith's map grants (+1 nodes / map packs).
  -------------------------------------------------------------------- */
  packStickerOdds: [[0.01, 4], [0.04, 3], [0.15, 2], [0.48, 1]],

  /* --------------------------------------------------------------------
     MYSTERY ("?") NODE EVENTS — arriving at a hidden map node rolls ONE of
     these outcomes (seeded by run seed + node id, so the same node always
     resolves the same way) and applies it on top of the underlying node.
     weights:           relative roll weight per outcome key. Boons:
                        coinBonus / cards / stickerPack / freeRemoval /
                        stickerStrip / joker / store; banes: cursedSticker /
                        coinLoss / ambush. The joker outcome folds to
                        coinBonus at apply time when the tier's jokerCap is
                        already full (deterministic, held-vs-cap).
     coinRangeByStage:  [min,max] coin amount for coinBonus/coinLoss, indexed
                        by stage (0-based; endless stages clamp to the last).
     cardGrantRange:    [min,max] how many cards the cards outcome grants
                        (suit-gated like a map pack: the current stage's suit,
                        all four suits for the alt decks).
     ambush:            the ambush deal — a subset of `cards` cards on `piles`
                        piles, paying `bounty` coins on a clear.
  -------------------------------------------------------------------- */
  mystery: {
    weights: {
      coinBonus: 15, cards: 12, stickerPack: 10, freeRemoval: 8,
      stickerStrip: 7, joker: 5, store: 5, cursedSticker: 14,
      coinLoss: 12, ambush: 8,
    },
    coinRangeByStage: [[6, 12], [12, 22], [20, 34]],
    cardGrantRange: [1, 3],
    ambush: { cards: 15, piles: 4, bounty: 15 },
  },

  /* --------------------------------------------------------------------
     ECONOMY — the flat deal payout (ECON1). Coins paid on a cleared deal:
       dealBase + stage × (1 + rating)
     stage  = the 1-based map phase (endless phases keep counting: 4, 5, …);
     rating = the deal's 1..3 stage-relative difficulty
              (RunMap.difficultyScore of the node's targetD). A boss forces
              rating 3 and adds bossBonus. Ambush deals pay NO flat base
              (their bounty is the reward). Anchor: a stage-1 easy deal pays
              dealBase + 1×(1+1) = 3 — dealBase is WHY the anchor is 3.
     Item-driven bonuses (Payout stickers, pillar payouts, the in-run event
     tally) pay ON TOP, unchanged — the flat base is the guaranteed income;
     items are how you get rich.
  -------------------------------------------------------------------- */
  economy: {
    dealBase: 1,    // flat base every cleared deal pays before the stage term
    bossBonus: 1,   // extra flat coins a cleared boss pays on top
  },

  /* --------------------------------------------------------------------
     PACKS — buying reveals `size` random items; the player keeps `keep`.
     Card-pack picks go to the pending pack tray (pre-run deck swap);
     sticker-pack picks go straight to the sticker inventory.
  -------------------------------------------------------------------- */
  packs: [
    { id: "cardPack", label: "Large Card Pack", icon: "🎴", kind: "card", tier: "uncommon",
      size: 5, keep: 2, price: 10,
      description: "Reveals 5 random cards. Keep 2 to swap into your deck before a deal, replacing a card of your choice." },
    { id: "smallCardPack", label: "Small Card Pack", icon: "🎴", kind: "card", tier: "common",
      size: 3, keep: 1, price: 8,
      description: "Reveals 3 random cards. Keep 1 to swap into your deck before a deal, replacing a card of your choice." },
    { id: "stickerPack", label: "Small Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 3, keep: 1, price: 5,
      description: "Reveals 3 random stickers. Keep 1 to add to a card." },
    { id: "largeStickerPack", label: "Large Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 5, keep: 2, price: 7,
      description: "Reveals 5 random stickers. Keep 2 for your inventory. The rest are discarded." }
  ],
};
