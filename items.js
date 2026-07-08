/* ============================================================================
   NINELIVES ITEM DATA — the single hand-editable source for EVERY shop item.

   Edit this file to tune the game: prices, rarities, store weights,
   descriptions, and every effect's numeric knobs live HERE. The game logic
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

   Malformed entries do NOT silently disappear: the game validates this file
   on load and fails loudly in the console with the offending item id.
============================================================================ */
"use strict";

const NINELIVES_ITEMS = {

  /* --------------------------------------------------------------------
     STORE CONFIG — offer weighting + the permanent Removal slot.
     tierWeights: relative chance a tier is rolled into a store slot
     (an item's own `weight` field, when present, overrides its tier's).
  -------------------------------------------------------------------- */
  store: {
    tierWeights: { common: 100, uncommon: 50, rare: 20 },
    // The debug-toggleable permanent 6th store slot: fixed price, never
    // depletes, each purchase runs the choose-a-card-to-remove flow.
    removal: {
      id: "removal", label: "Removal", icon: "∅", price: 20,
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
      description: "-2 card rank (stops at 2)." },
    { id: "randomFixedValue", label: "Random Rank", icon: "🎰", kind: "behavior", behavior: "randomFixedValue", tier: "uncommon", price: 1,
      description: "Set card to random rank" },
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
    { id: "tieSafe",    label: "Same-Safe",   icon: "🛡️", kind: "behavior", behavior: "tieSafe", tier: "common", price: 2,
      description: "Automatically safe if lands on same value card (even if higher or lower is guessed)" },
    { id: "suitImmunity", label: "Spade Guard", icon: "♠️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♠", tier: "uncommon", price: 3,
      description: "If card is drawn onto a ♠ card it is safe from a wrong guess" },
    { id: "heartGuard", label: "Heart Guard", icon: "♥️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♥", tier: "uncommon", price: 3,
      description: "If card is drawn onto a ♥ card it is safe from a wrong guess" },
    { id: "diamondGuard", label: "Diamond Guard", icon: "♦️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♦", tier: "uncommon", price: 3,
      description: "If card is drawn onto a ♦ card it is safe from a wrong guess" },
    { id: "clubGuard",  label: "Club Guard",  icon: "♣️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♣", tier: "uncommon", price: 3,
      description: "If card is drawn onto a ♣ card it is safe from a wrong guess" },
    // value = coins per Extra Coin UNIT (units = stickers on the alive top card
    // × cards in that pile; Economy multiplies units by this value).
    { id: "extraCoin",  label: "Payout",      icon: "💰", kind: "behavior", behavior: "extraCoin", value: 1, tier: "uncommon", price: 2,
      description: "Earn coins equal to pile size if this card is top of pile at end of deal", suits: ["♥"] },
    { id: "middleColumnReward", label: "Middle", icon: "🎯", kind: "behavior", behavior: "middleColumnReward", value: 4, tier: "uncommon", price: 2,
      description: "+3 coins if in middle column", suits: ["♥"] },
    { id: "gainCoin",   label: "Bonus Coin",  icon: "🍀", kind: "behavior", behavior: "gainCoin", value: 1, tier: "common", price: 2,
      description: "+1 coin", suits: ["♥"] },
    { id: "anchor",     label: "Anchor",      icon: "⚓", kind: "behavior", behavior: "anchor", tier: "common", price: 3,
      description: "If this is the top card, the pile is left out of the smallest-pile score", suits: ["♦"] },
    { id: "extraHeart", label: "Shield",      icon: "❤️", kind: "behavior", behavior: "extraHeart", tier: "rare", price: 5,
      description: "When a drawn card lands wrong on this pile card, the pile survives and the drawn card returns to the deck, then the shield is drained until next deal" },
    { id: "oneTribute", label: "Bury 1",      icon: "🪦", kind: "behavior", behavior: "tribute", tributeCount: 1, coinCost: 4, tier: "rare", price: 10,
      description: "Bury 1 deck card under the pile and -3 coins", suits: ["♣"] },
    { id: "twoTribute", label: "Bury 2",      icon: "⚰️", kind: "behavior", behavior: "tribute", tributeCount: 2, coinCost: 4, tier: "rare", price: 16,
      description: "Optionally bury 2 deck cards and -4 coins", suits: ["♣"]  },
    { id: "centerTribute", label: "Middle Bury", icon: "🗿", kind: "behavior", behavior: "tribute", tributeCount: 1, centerOnly: true, tier: "rare", price: 4,
      description: "Bury 1 deck card under the pile if in middle column", suits: ["♣"]  },
    { id: "deathBounty", label: "Last Coin",  icon: "💀", kind: "behavior", behavior: "deathBounty", value: 5, tier: "common", price: 3,
      description: "Gain +5 coins if this card kills a pile", suits: ["♥"] },
    // value = extra pile-size weight per Heavy sticker on a card.
    { id: "heavy",      label: "Heavy",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 1, tier: "common", price: 2,
      description: "+1 toward pile size",suits: ["♦"]  },
    { id: "collector",  label: "Collector",   icon: "🧲", kind: "behavior", behavior: "collector", value: 2, tier: "uncommon", price: 2,
      description: "+2 coins per other sticker on this card", suits: ["♥"] },
    // step = coins the payout grows per correct placement (pays 0 on the first).
    { id: "compound",   label: "Compound",    icon: "📈", kind: "behavior", behavior: "compound", step: 1, tier: "rare", price: 2,
      description: "Earn X coins. X starts at 0 and grows by 1 after each correct placement", suits: ["♥"] },
    { id: "revealNext", label: "Scout",       icon: "👁️", kind: "behavior", behavior: "revealNext", tier: "rare", price: 12,
      description: "Peek at the next deck card", suits: ["♠"]  },
    { id: "wildSuit",   label: "Wild Suit",   icon: "♠♥♦♣", kind: "behavior", behavior: "wildSuit", tier: "common", price: 2,
      description: "Counts as every suit" },
    { id: "shuffle",    label: "Shuffle",     icon: "🔀", kind: "behavior", behavior: "shuffle", tier: "uncommon", price: 2,
      description: "Optionally shuffle the pile", suits: ["♦"]  },
    // count = buried cards moved to the smallest pile per accepted Donate.
    { id: "donate",     label: "Donate",      icon: "🤝", kind: "behavior", behavior: "donate", count: 1, tier: "common", price: 1,
      description: "Move 1 buried card from pile card is placed on to the smallest pile", suits: ["♦"]  },
    // peelChance = probability (0–1) the sticker destroys itself after burying.
    { id: "quickBury",  label: "Quick Bury",  icon: "⚡", kind: "behavior", behavior: "quickBury", peelChance: 0.25, tier: "uncommon", price: 7,
      description: "Bury 1 deck card under the pile, then a 25% chance this sticker peels", suits: ["♣"]  },
    { id: "twinSpark",  label: "Twin Spark",  icon: "✨", kind: "behavior", behavior: "twinSpark", tier: "rare", price: 5,
      description: "Peek next card if the top card of another pile has the same rank as this card", suits: ["♠"]  },
    // max = the top of the random 0–max coin roll.
    { id: "looseChange", label: "Loose Change", icon: "🪙", kind: "behavior", behavior: "looseChange", max: 3, tier: "uncommon", price: 4,
      description: "+0–3 coins random each time", suits: ["♥"] },
    // step = how much X (cards buried) grows per correct placement.
    { id: "snowball",   label: "Snowball Bury", icon: "☃️", kind: "behavior", behavior: "snowball", step: 1, tier: "rare", price: 20,
      description: "Bury X cards under the pile. X starts at 0 and grows by 1 each correct placement. A wrong guess resets it to 0.", suits: ["♣"] },
    // per = deck cards per +1 coin (floor(deck remaining ÷ per)).
    { id: "deepPockets", label: "Deep Pockets", icon: "👛", kind: "behavior", behavior: "deepPockets", per: 10, tier: "uncommon", price: 2,
      description: "+1 coin per 10 cards left in the deck", suits: ["♥"]},
    { id: "pillarScout", label: "Pillar Scout", icon: "🔭", kind: "behavior", behavior: "pillarScout", tier: "uncommon", price: 3,
      description: "Peek at the next deck card if this card lands in column with no Pillar", suits: ["♠"]  },
    { id: "baseScout",  label: "Base Scout",  icon: "🔎", kind: "behavior", behavior: "baseScout", tier: "uncommon", price: 3,
      description: "Peek at the next card if in a column with no Base", suits: ["♠"]  },
    { id: "suitSnob",   label: "Suit Snob",   icon: "🧐", kind: "behavior", behavior: "suitSnob", tier: "uncommon", price: 3,
      description: "Peek at next deck card if this card lands on a ♠ card", suits: ["♠"]  },
    // step = coins X grows per correct placement (resets to 0 on a wrong one).
    { id: "momentum",   label: "Momentum",    icon: "🎢", kind: "behavior", behavior: "momentum", step: 2, tier: "rare", price: 2,
      description: "Earn X coins. X starts at 0 and grows by 2 after each correct placement. An incorrect guess resets X to 0", suits: ["♥"] },
    { id: "tell",       label: "Tell",        icon: "🔮", kind: "behavior", behavior: "tell", tier: "uncommon", price: 7,
      description: "Tells you if the next drawn card is higher, lower, or same as this card", suits: ["♠"] },
    // ---- Same-charge / Same-power stickers (fire on correct placement) ----
    { id: "rechargeSameShield", label: "Recharge Shield", icon: "🛡️", kind: "behavior", behavior: "rechargeSameShield", tier: "rare", price: 15,
      description: "Trigger: Correct placement of this card\nEffect: Bank a Same Charge — the auto-save shield (max 1; does nothing if already charged)" },
    { id: "activateSamePower", label: "Tap Power", icon: "🔗", kind: "behavior", behavior: "activateSamePower", tier: "rare", price: 12,
      description: "Trigger: Correct placement of this card\nEffect: Fire your equipped Same-Power on this card's pile (its linked piles). Does not bank a charge; nothing if no Same-Power is equipped" },
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
      description: "+1 coin each time a ♥ card lands in this column" },
    { id: "columnTieSafe", label: "Column Tie-Safe", icon: "🛡️",
      kind: "guess", effect: "columnTieSafe", tier: "rare", price: 12,
      description: "Trigger: Passive\nEffect: Every pile in this column survives a tie" },
    { id: "columnGuardian", label: "Guardian", icon: "🏛️",
      kind: "scoring", effect: "columnAllAlive", value: 7, tier: "uncommon", price: 7,
      description: "+7 coins if every pile in this column is alive at end of deal" },
    // digCount = deck cards buried per qualifying (sticker-free ♣) landing.
    { id: "clubTribute", label: "8 Bury", icon: "8️⃣",
      kind: "composition", effect: "clubTribute", digCount: 1, tier: "rare", price: 25,
      description: "Bury a card if a ♣ card with no stickers lands correctly in this column" },
    { id: "allHeartsCoin", label: "All Hearts", icon: "💗",
      kind: "scoring", effect: "allSuitTop", suit: "♥", value: 8, tier: "common", price: 8,
      description: "+8 coins at end of deal if every surviving pile in this column shows a ♥ on top" },
    // value = coins per alive ♥-topped pile in this column at end of deal.
    { id: "envy", label: "Envy", icon: "💚",
      kind: "scoring", effect: "heartPiles", value: 4, tier: "common", price: 8,
      description: "Trigger: End of deal\nEffect: +4 coins for each pile in this column whose top card is a ♥ (counted per pile)" },
    // threshold = the in-column streak step the bonus starts at (+1 size per
    // step from there on; resets on a wrong guess or any other-column guess).
    { id: "streakBank", label: "Streak Size", icon: "🏦",
      kind: "modifier", effect: "streakSize", threshold: 3, tier: "rare", price: 8,
      description: "+1 pile size per consecutive correct guess in this column, from the 3rd guess onward. Resets on a wrong guess or any guess in another column" },
    // threshold = the streak step burials start at; digCount = cards buried
    // per correct in-column guess from that step onward (flat, no escalation).
    { id: "streakTribute", label: "Streak Bury", icon: "🔥",
      kind: "composition", effect: "streakTribute", threshold: 3, digCount: 1, tier: "rare", price: 20,
      description: "Bury 1 deck card per consecutive correct guess in this column, from the 3rd guess onward. Resets on a wrong guess or any guess in another column" },
    { id: "secondWind", label: "Second Wind", icon: "🌬️",
      kind: "guess", effect: "secondWind", tier: "rare", price: 12,
      description: "The first pile in this column to die is saved, but all buried cards in that pile are returned to the deck" },
    { id: "greedy", label: "Greedy", icon: "🤑",
      kind: "scoring", effect: "greedy", value: 20, tier: "rare", price: 10,
      description: "Trigger: Deal cleared\nEffect: +20 coins if every pile in this column survived AND no other Pillar is on the board" },
    // value = coins per Fibonacci-rank (A/2/3/5/8) card drawn into the column.
    { id: "fibonacci", label: "Fibonacci", icon: "🌀",
      kind: "live", effect: "fibonacci", value: 1, tier: "rare", price: 8,
      description: "+1 coin each time a Fibonacci-rank card (A/2/3/5/8) is drawn into this column, whether the guess is right or wrong" },
    { id: "highestOdd", label: "Highest Odd", icon: "🔼",
      kind: "scoring", effect: "highestOdd", tier: "rare", price: 12,
      description: "Receive coins equal to the highest odd-rank (3/5/7/9) top card in this column at end of deal" },
    { id: "highestEven", label: "Highest Even", icon: "🔽",
      kind: "scoring", effect: "highestEven", tier: "rare", price: 15,
      description: "Receive coins equal to the highest even-rank (2/4/6/8/10) top card in this column at end of deal" },
    // minStickers = stickers a landing ♣ must carry; digCount = cards buried.
    { id: "denseBury", label: "Dense Bury", icon: "🧊",
      kind: "composition", effect: "denseBury", minStickers: 2, digCount: 1, tier: "rare", price: 20,
      description: "Bury a card if a ♣ card carrying 2+ stickers lands correctly in this column" },
    // trigger = the pile size (cards) that arms the one-shot revive offer.
    { id: "revive", label: "Revive", icon: "♻️",
      kind: "guess", effect: "revive", trigger: 10, tier: "rare", price: 25,
      description: "Immediately revive one dead pile on the board if a pile in this column reaches 10 cards" },
    // ---- expansion Pillars ------------------------------------------------
    { id: "insurance", label: "Insurance", icon: "🛟",
      kind: "scoring", effect: "insurance", value: 20, tier: "rare", price: 8,
      description: "+20 coins if only one pile alive at end of deal and it's in this column" },
    { id: "ditto", label: "Ditto", icon: "🪞",
      kind: "meta", effect: "ditto", tier: "rare", price: 9,
      description: "Mirror the center column's Pillar" },
    // value = extra pile size per ♦ card (top or buried) in the column.
    { id: "stickerCount", label: "Heavy Diamond", icon: "🏷️",
      kind: "modifier", effect: "heavyDiamond", value: 1, tier: "uncommon", price: 7,
      description: "Diamond ♦ cards in this column all count as +1 toward pile size" },
    // value = coins per prime-rank (2/3/5/7) card landing correctly here.
    { id: "prime", label: "Prime", icon: "🔢",
      kind: "live", effect: "prime", value: 1, tier: "uncommon", price: 6,
      description: "Trigger: A prime-rank card (2/3/5/7) lands correctly in this column\nEffect: +1 coin" },
    { id: "queensEye", label: "Queen's Eye", icon: "👁️",
      kind: "live", effect: "queensEye", tier: "uncommon", price: 8,
      description: "Peek next card if a royal (J/Q/K) spade ♠ card lands correctly in this column" },
    { id: "royalCourt", label: "Shuffler", icon: "👑",
      kind: "guess", effect: "shuffler", tier: "uncommon", price: 5,
      description: "Shuffle other piles in this column if a ♦ lands in this column" },
    // value = coins per buried card in the largest ♥-topped alive pile.
    { id: "excavator", label: "Excavator", icon: "⛏️",
      kind: "scoring", effect: "excavator", value: 2, tier: "uncommon", price: 6,
      description: "+2 coins per buried card in this column's largest pile with a ♥ top card at end of deal" },
    // chance = probability (0–1) the flip pays `value` (needs a ♥ top here).
    { id: "gambler", label: "Gambler", icon: "🎲",
      kind: "scoring", effect: "gambler", value: 10, chance: 0.5, tier: "uncommon", price: 10,
      description: "50/50 chance to receive +10 coins or nothing if there is a ♥ top card in column at end of deal" },
    { id: "broadcast", label: "Broadcast", icon: "📡",
      kind: "modifier", effect: "broadcast", tier: "rare", price: 18,
      description: "All base powers are applied to entire board when triggered instead of just their columns" },
    { id: "lastRites", label: "Last Rites", icon: "🕯️",
      kind: "live", effect: "lastRites", tier: "rare", price: 25,
      description: "Peek the next upcoming card if a pile in this column dies" },
    // selfDestruct = probability (0–1) the Pillar destroys itself each deal end.
    { id: "static", label: "Static", icon: "🔌",
      kind: "live", effect: "static", selfDestruct: 0.25, tier: "rare", price: 6,
      description: "Peek the next card if a ♠ card lands in this column; 25% chance pillar is destroyed at end of each deal" },
    { id: "wildAces", label: "Wild Aces", icon: "🃏",
      kind: "guess", effect: "wildAces", tier: "rare", price: 25,
      description: "Aces count as high or low when landing in this column" },
    { id: "diamondAnchor", label: "Diamond Anchor", icon: "⚓",
      kind: "modifier", effect: "diamondAnchor", tier: "rare", price: 12,
      description: "If a diamond ♦ card is the top card, the pile is left out of the smallest-pile score" },
    { id: "diamondDistribution", label: "Diamond Distribution", icon: "⚖️",
      kind: "guess", effect: "diamondDistribution", tier: "uncommon", price: 6,
      description: "Redistribute all piles in column to make pile sizes even if a diamond ♦ lands in this column" },
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
      kind: "active", effect: "kamikaze", target: "pile", peekCount: 3, tier: "rare", price: 15,
      description: "Trigger: Activated (tap a ♠ pile), once per deal\nEffect: Kill a chosen pile with a ♠ top card, then peek the next 3 upcoming cards (draw order unchanged). Unavailable while only one pile is alive" },
    { id: "spadePeek", label: "Spade Peeker", icon: "🔦",
      kind: "active", effect: "spadePeek", tier: "rare", price: 15,
      description: "Trigger: Activated, once per deal\nEffect: Peek the next X upcoming cards, where X is the number of piles in this column whose top card is a printed ♠ (Wild Suit tops don't count)" },
    // coinPerPile = coins LOST per pile shuffled.
    { id: "shuffleColumn", label: "Upheaval", icon: "🌀",
      kind: "active", effect: "shuffleColumn", coinPerPile: 1, tier: "common", price: 9,
      description: "Trigger: Activated, once per deal\nEffect: Shuffle every pile in this column (a different card may top each; order stays hidden). Lose 1 coin for each shuffled pile" },
    { id: "revive", label: "Phoenix", icon: "🔥",
      kind: "active", effect: "reviveBase", tier: "uncommon", price: 14,
      description: "Trigger: Activated, once per deal\nEffect: Revive a random dead pile in this column with one fresh pile card (its buried cards shuffle into the deck). Nothing if none is dead" },
    { id: "randomSticker", label: "Wild Sticker", icon: "🎲",
      kind: "active", effect: "randomSticker", tier: "uncommon", price: 5,
      description: "Trigger: Activated, once per deal\nEffect: Apply a random sticker to a random top pile card in this column. Lasts the rest of the run" },
    { id: "evenOut", label: "Ballast", icon: "🪨",
      kind: "active", effect: "evenOut", tier: "common", price: 9,
      description: "Trigger: Activated, once per deal\nEffect: Distribute the piles in this column that hold ♦ cards (top card or buried) so they end up the same pile size (composition only — nothing revealed)" },
    // digCount = cards buried under each ♣-topped pile; coinPerCard = coins
    // LOST per card buried.
    { id: "buryAll", label: "Landslide", icon: "⛰️",
      kind: "active", effect: "buryAll", suit: "♣", digCount: 2, coinPerCard: 3, tier: "rare", price: 10,
      description: "Trigger: Activated, once per deal\nEffect: Bury 2 deck cards under each pile with a ♣ top card in this column. Lose 3 coins per card buried" },
    { id: "setValue", label: "Cast", icon: "🗿",
      kind: "active", effect: "setValue", tier: "rare", price: 12,
      description: "Trigger: Activated, once per deal\nEffect: Permanently set the rank of every top pile card in this column to the rank of the bottom pile in the column. Lasts the rest of the run" },
    { id: "setSuit", label: "Suit Setter", icon: "🎨",
      kind: "active", effect: "setSuit", tier: "rare", price: 18,
      description: "Trigger: Activated, once per deal\nEffect: Permanently set the suit of every top pile card in this column to the suit of the bottom pile in the column. Lasts the rest of the run" },
    // buryPerSticker = deck cards buried per sticker peeled off the pile card.
    { id: "stickerHarvest", label: "Sticker Harvest", icon: "🌾",
      kind: "active", effect: "stickerHarvest", target: "pile", buryPerSticker: 2, tier: "uncommon", price: 11,
      description: "Trigger: Activated (choose a pile), once per deal\nEffect: Bury 2 deck cards under the chosen pile per sticker on its pile card, then peel those stickers off it" },
    { id: "refreshBases", label: "Reactor", icon: "⚛️",
      kind: "active", effect: "refreshBases", tier: "rare", price: 17,
      description: "Trigger: Activated, once per deal\nEffect: Recharge your other two Bases if they've been spent this deal (never another Reactor)" },
    // ---- expansion Bases --------------------------------------------------
    // digCount = cards buried under each matching-suit-topped pile.
    { id: "clubDig", label: "Club Dig", icon: "♣️",
      kind: "active", effect: "suitDig", suit: "♣", digCount: 1, tier: "rare", price: 15,
      description: "Trigger: Activated, once per deal\nEffect: Bury 1 deck card under each pile with a ♣ top card in this column" },
    // reward = coins gained for destroying the chosen Pillar.
    { id: "demolish", label: "Demolish", icon: "🔨",
      kind: "active", effect: "demolish", target: "pillar", reward: 15, tier: "uncommon", price: 25,
      description: "Trigger: Activated (choose a Pillar), once per deal\nEffect: Destroy the chosen placed Pillar for good; gain +15 coins" },
    // coinPerPile = coins gained per ♥-topped pile destroyed.
    { id: "heartDemolish", label: "Heart Demolish", icon: "💔",
      kind: "active", effect: "heartDemolish", coinPerPile: 7, tier: "uncommon", price: 10,
      description: "Trigger: Activated, once per deal\nEffect: Destroy every pile in this column with a ♥ top card and gain +7 coins per pile destroyed" },
    // coinPerCard = coins gained per ♥ card counted in the column.
    { id: "tax", label: "Heart Tax", icon: "🧾",
      kind: "active", effect: "tax", suit: "♥", coinPerCard: 1, tier: "uncommon", price: 9,
      description: "Trigger: Activated, once per deal\nEffect: +1 coin for each ♥ card in this column (includes top cards and buried; dead piles don't count)" },
    // ---- Same-charge / Same-power bases (activated, once per deal) ----
    { id: "rechargeSame", label: "Recharge Cell", icon: "🔋",
      kind: "active", effect: "rechargeSameShield", tier: "rare", price: 25,
      description: "Trigger: Activated, once per deal\nEffect: Bank a Same Charge — the auto-save shield (max 1; unavailable while already charged)" },
    { id: "activateSame", label: "Power Surge", icon: "⚡",
      kind: "active", effect: "activateSamePower", tier: "rare", price: 20,
      description: "Trigger: Activated, once per deal\nEffect: Fire your equipped Same-Power on a random pile in this column (its linked piles). Does not bank a charge; needs a Same-Power equipped" },
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
      description: "Trigger: You make a correct Same\nEffect: Revive one dead pile directly linked to the pile you called Same on, keeping its size" },
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
    // value = pile size added to each directly-linked pile (lasts the deal).
    { id: "linkHeavy", label: "Same Heavy", icon: "🧱",
      effect: "linkHeavy", value: 5, tier: "rare", price: 5,
      description: "Trigger: You make a correct Same\nEffect: Add +5 pile size to each pile directly linked to the pile you called Same on" },
  ],

  /* --------------------------------------------------------------------
     PACKS — buying reveals `size` random items; the player keeps `keep`.
     Card-pack picks go to the pending pack tray (pre-run deck swap);
     sticker-pack picks go straight to the sticker inventory.
  -------------------------------------------------------------------- */
  packs: [
    { id: "cardPack", label: "Large Card Pack", icon: "🎴", kind: "card", tier: "common",
      size: 5, keep: 1, price: 10,
      description: "Reveals 5 random cards. Keep 1 to swap into your deck before a deal, replacing a card of your choice. The rest are discarded." },
    { id: "smallCardPack", label: "Small Card Pack", icon: "🎴", kind: "card", tier: "common",
      size: 3, keep: 1, price: 8,
      description: "Reveals 3 random cards. Keep 1 to swap into your deck before a deal, replacing a card of your choice. The rest are discarded." },
    { id: "stickerPack", label: "Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 3, keep: 1, price: 5,
      description: "Reveals 3 random stickers. Keep 1 for your inventory. The rest are discarded." },
  ],
};
