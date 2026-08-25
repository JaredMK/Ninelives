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
                  threshold, digCount, chance, …) — safe to hand-edit
     unlock       OPTIONAL item-unlock gate: { type, stat, count }. ABSENT = a
                  starting item, always available — the ship state: no entry
                  carries this field, so every roll pool is identical to the
                  pre-feature game. When set, the item stays out of every roll
                  pool (sticker grants, store classes, sticker packs, Lammy's
                  pre-equip) until the LIFETIME counter `stat` (the Stats
                  record, ninelives.stats.v1) reaches `count`. `type` is
                  documentary — "milestone" (progression counters) or
                  "behavior" (playstyle counters); both gate identically and
                  it only flavors the hint copy. `stat` is one of these 30:

                  PROGRESSION
                    dealsSurvived      runsPlayed        runsWon
                    bossesBeaten       endlessStagesReached
                  SPENDING + ECONOMY
                    coinsEarnedLifetime                  (lifetime total)
                    bestCoinsInClimb   (native) most coins EARNED in one climb
                    bestCampaignScore  (native) best campaign score reached
                  PLAYSTYLE
                    cardsBuried        samesCalled       correctSames
                    jokersPlayed       stickersApplied   pillarsPlaced
                    basesPlaced        removalsUsed      pilesLost
                  SUITS LANDED (native) — follows how the player really plays
                    heartsPlayed       diamondsPlayed
                    clubsPlayed        spadesPlayed
                  PRECISION + DIFFICULTY (native)
                    perfectDeals       (deals cleared with NO wrong guess)
                    dealsWonRegular    dealsWonMaster    dealsWonLegendary
                  CURIOSITY (native)
                    pinkyTipsSeen      (climbs in which the map's bottom tip
                                        was found — once per climb)
                  ZEN — reachable before ANY campaign progress, so these are
                  the early on-ramp for a brand-new player
                    zenGamesPlayed     zenEasyWon        zenMediumWon
                    zenHardWon
                  `count` is a positive finite number. A malformed gate fails
                  loudly at load (the validator names the item id).
                  Example (keep it COMMENTED — no live unlock field ships
                  without the full feature pass):
   // { id: "example", label: "…", tier: "rare", price: 10, description: "…",
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
  // A card may never carry more than this many stickers. The pickers grey out
  // a full card and every grant path (packs, Wild Sticker, mystery, the Old
  // Joker's leech) checks it, so a card can't be stacked past readability.
  maxStickersPerCard: 4,

  store: {
    slots: 6,
    typeCap: 3,
    reroll: { baseCost: 5, step: 1 },
    classWeights: { sticker: 40, pillar: 20, base: 15, card: 10, pack: 10, samepower: 5 },
    tierWeights: { common: 100, uncommon: 50, rare: 20 },
    // MYSTERY SAME-POWER: the samepower class no longer rolls a concrete
    // Same-Power onto the shelf. It yields ONE unknown slot at this fixed
    // price; the actual Same-Power is rolled (seeded) at buy time and the
    // player then keeps (equips) or discards it. The class weight above is
    // unchanged, so the shelf encounter rate matches the old individual
    // same-power rate.
    mysterySamePower: {
      label: "Mystery Same-Power", icon: "❓", price: 10,
      description: "Purchase to reveal",
    },
    // The INDIVIDUAL-CARD slot: one playing card, rolled with the same
    // odds it would have inside a card pack (suits in play, the same
    // chance of carrying stickers, Mr. Smith's rates where applicable).
    // Removal cards never appear here. A Joker may roll in at the plain
    // any-card rate (1/53) but costs jokerPrice instead of price; the
    // difficulty tier's joker cap applies (none on Legendary).
    card: {
      label: "Card", icon: "🂠", price: 3, jokerPrice: 25,
      // Each sticker the minted card carries adds `stickerStep` to the price,
      // and the card slot rolls its OWN sticker table (not packStickerOdds):
      // 1% → 3 stickers, 5% → 2, 25% → 1, else clean.
      stickerStep: 1,
      stickerOdds: [[0.01, 3], [0.06, 2], [0.31, 1]],
      description: "A single card. Swap it into your deck",
    },
    // The debug-toggleable permanent 6th store slot: fixed price, never
    // depletes, each purchase runs the choose-a-card-to-remove flow.
    // `priceStep` makes the slot climb: every removal bought in a climb adds
    // this much to the next one's price (0 = flat forever). The ladder resets
    // with each new climb, like the reroll ladder resets each shop visit.
    removal: {
      id: "removal", label: "Purge", icon: "∅", price: 5, priceStep: 2,
      description: "Permanently remove a card from your deck. Purge price climbs each time",
    },
    // SELL values by tier — what the store pays when an equipped item is
    // sold. THE one source: the UI must read these, never hardcode them
    // (the Old Joker's refund multiplies these same bases by minMult..maxMult).
    sell: { common: 1, uncommon: 2, rare: 3 },
  },

  /* --------------------------------------------------------------------
     STICKERS — card-bound modifiers ("Imprints"). A card may hold any
     number of stickers, duplicates included. `rankDelta`, `tributeCount`,
     `coinCost`, `value`, `step`, `per`, `max`, `count` are
     effect knobs.
     SUIT-TIMING PRICING convention: a ♣ item costs its ♦/♥ twin's price −1;
     a ♠ item costs −2 (floor 1).
  -------------------------------------------------------------------- */
  stickers: [
    { id: "rankUp",     label: "+1 Rank",     icon: "➕", kind: "rank",     rankDelta: 1,  tier: "common",   price: 1,
      description: "+1 card rank (stops at Ace)"},
    { id: "rankDown",   label: "−1 Rank",     icon: "➖", kind: "rank",     rankDelta: -1, tier: "common",   price: 1,
      description: "-1 card rank (stops at 2)" },
    { id: "rankUp2", unlock: { type: "milestone", stat: "dealsWonRegular", count: 4 }, label: "+2 Rank",     icon: "⏫", kind: "rank",     rankDelta: 2,  tier: "uncommon", price: 2,
      description: "+2 card rank (stops at Ace)" },
    { id: "rankDown2", unlock: { type: "milestone", stat: "dealsSurvived", count: 12 }, label: "−2 Rank",     icon: "⏬", kind: "rank",     rankDelta: -2, tier: "uncommon", price: 2,
      description: "-2 card rank (stops at 2)" },
    { id: "randomFixedValue", unlock: { type: "milestone", stat: "runsPlayed", count: 3 }, label: "Random Rank", icon: "🎰", kind: "behavior", behavior: "randomFixedValue", tier: "uncommon", price: 1,
      description: "Change to random rank" },
    { id: "changeSuitRandom", label: "Random Suit", icon: "🎲", kind: "behavior", behavior: "changeSuitRandom", tier: "common", weight: 25, price: 1,
      description: "Change to random suit" },
    { id: "changeSuitSpade",  label: "Change to ♠", icon: "♠️", kind: "behavior", behavior: "changeSuitTo", suit: "♠", tier: "common", weight: 25, price: 1,
      description: "Change suit to ♠" },
    { id: "changeSuitHeart",  label: "Change to ♥", icon: "♥️", kind: "behavior", behavior: "changeSuitTo", suit: "♥", tier: "common", weight: 25, price: 1,
      description: "Change suit to ♥" },
    { id: "changeSuitDiamond", label: "Change to ♦", icon: "♦️", kind: "behavior", behavior: "changeSuitTo", suit: "♦", tier: "common", weight: 25, price: 1,
      description: "Change suit to ♦" },
    { id: "changeSuitClub",   label: "Change to ♣", icon: "♣️", kind: "behavior", behavior: "changeSuitTo", suit: "♣", tier: "common", weight: 25, price: 1,
      description: "Change suit to ♣" },
    { id: "tieSafe",    label: "Same-Safe",   icon: "🛡️", kind: "behavior", behavior: "tieSafe", tier: "common", price: 2,
      description: "Safe if this card lands on a card of the same rank, or a card of the same rank lands on this card" },
    // Guards only ride cards of THEIR OWN suit (`suits` gates placement —
    // store picker, packs, every grant path honours it).
    { id: "suitImmunity", unlock: { type: "behavior", stat: "spadesPlayed", count: 150 }, label: "Spade Guard", icon: "♠️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♠", suits: ["♠"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♠, or a ♠ lands on this card" },
    { id: "heartGuard", unlock: { type: "milestone", stat: "dealsSurvived", count: 25 }, label: "Heart Guard", icon: "♥️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♥", suits: ["♥"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♥, or a ♥ lands on this card" },
    { id: "diamondGuard", unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 100 }, label: "Diamond Guard", icon: "♦️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♦", suits: ["♦"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♦, or a ♦ lands on this card" },
    { id: "clubGuard", unlock: { type: "behavior", stat: "cardsBuried", count: 120 }, label: "Club Guard",  icon: "♣️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♣", suits: ["♣"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♣, or a ♣ lands on this card" },
    // value = coins per Extra Coin UNIT (units = stickers on the alive top card
    // × cards in that pile; Economy multiplies units by this value).
    { id: "extraCoin",  unlock: { type: "behavior", stat: "perfectDeals", count: 1 }, label: "Payout",      icon: "💰", kind: "behavior", behavior: "extraCoin", value: 1, tier: "uncommon", price: 3,
      description: "At deal end if this card tops its pile  → earn coins equal to pile size", suits: ["♥"] },
    { id: "gainCoin",   label: "Bonus Coin",  icon: "🍀", kind: "behavior", behavior: "gainCoin", value: 1, tier: "common", price: 2,
      description: "+1 coin", suits: ["♥"] },
    { id: "anchor",     label: "Anchor",      icon: "⚓", kind: "behavior", behavior: "anchor", tier: "common", price: 2,
      description: "At deal end → exclude pile from the smallest-pile score if this card is on top", suits: ["♦"] },
    { id: "deathBounty", label: "Last Coin",  icon: "💀", kind: "behavior", behavior: "deathBounty", value: 3, tier: "common", price: 2,
      description: "+3 coins if it kills a pile", suits: ["♥"] },
    // value = extra pile-size weight per Heavy sticker on a card.
    { id: "heavy",      label: "Heavy",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 1, tier: "common", price: 1,
      description: "+1 pile size",suits: ["♦"]  },
     { id: "massive", unlock: { type: "behavior", stat: "stickersApplied", count: 10 }, label: "Massive",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 2, tier: "uncommon", price: 2,
      description: "+2 pile size",suits: ["♦"]  },
    { id: "collector", unlock: { type: "behavior", stat: "stickersApplied", count: 90 }, label: "Collector",   icon: "🧲", kind: "behavior", behavior: "collector", value: 1, tier: "uncommon", price: 1,
      description: "+1 coin per other sticker on this card", suits: ["♥"] },
    // step = coins the payout grows per correct placement (pays 0 on the first).
    { id: "compound", unlock: { type: "milestone", stat: "bestCampaignScore", count: 120 }, label: "Compound",    icon: "📈", kind: "behavior", behavior: "compound", step: 1, tier: "rare", price: 6,
      description: "+X coins. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess", suits: ["♥"] },
    { id: "revealNext", unlock: { type: "behavior", stat: "zenEasyWon", count: 2 }, label: "Scout",       icon: "👁️", kind: "behavior", behavior: "revealNext", tier: "rare", price: 10,
      description: "Peek at the next deck card", suits: ["♠"]  },
    { id: "wildSuit",   label: "Wild Suit",   icon: "♠♥♦♣", kind: "behavior", behavior: "wildSuit", tier: "common", price: 1,
      description: "Counts as every suit" },
    { id: "shuffle", label: "Shuffle",     icon: "🔀", kind: "behavior", behavior: "shuffle", tier: "uncommon", price: 1,
      description: "Optionally shuffle the pile", suits: ["♦"]  },
    // count = buried cards moved to the smallest pile per accepted Donate.
    { id: "donate",     label: "Donate",      icon: "🤝", kind: "behavior", behavior: "donate", count: 1, tier: "common", price: 1,
      description: "Move 1 buried card from this pile to the smallest pile", suits: ["♦"]  },
    // UNGATED on purpose: with Bury 1 retired, Quick Bury is the cardsBuried
    // unlock ladder's only seed source (chicken-and-egg otherwise).
    // v6.78: fires on the CARRIER's own landing (was pile-top since v6.75).
    { id: "quickBury", label: "Quick Bury",  icon: "⚡", kind: "behavior", behavior: "quickBury", tier: "uncommon", price: 7,
      description: "When this card lands → bury 1 card under the pile", suits: ["♣"]  },
    { id: "twinSpark", unlock: { type: "behavior", stat: "zenGamesPlayed", count: 4 }, label: "Twin Spark",  icon: "✨", kind: "behavior", behavior: "twinSpark", tier: "uncommon", price: 3,
      description: "Peek at the next card if another pile's top card matches this rank", suits: ["♠"]  },
    // max = the top of the random 0–max coin roll.
    { id: "looseChange", unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 60 }, label: "Loose Change", icon: "🪙", kind: "behavior", behavior: "looseChange", max: 3, tier: "uncommon", price: 2,
      description: "+0–3 coins (random)", suits: ["♥"] },
    // step = how much X (cards buried) grows per correct placement.
    { id: "snowball", unlock: { type: "behavior", stat: "perfectDeals", count: 6 }, label: "Snowball Bury", icon: "☃️", kind: "behavior", behavior: "snowball", step: 1, tier: "rare", price: 10,
      description: "Bury X cards. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess", suits: ["♣"] },
    // per = deck cards per +1 coin (floor(deck remaining ÷ per)).
    { id: "deepPockets", unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 140 }, label: "Deep Pockets", icon: "👛", kind: "behavior", behavior: "deepPockets", per: 10, tier: "uncommon", price: 3,
      description: "+1 coin per 10 cards left in the deck", suits: ["♥"]},
    { id: "pillarScout", unlock: { type: "behavior", stat: "pillarsPlaced", count: 12 }, label: "Pillar Scout", icon: "🔭", kind: "behavior", behavior: "pillarScout", tier: "uncommon", price: 2,
      description: "Peek the next card if this column has no pillar", suits: ["♠"]  },
    { id: "baseScout", unlock: { type: "behavior", stat: "basesPlaced", count: 12 }, label: "Base Scout",  icon: "🔎", kind: "behavior", behavior: "baseScout", tier: "uncommon", price: 2,
      description: "Peek at the next card if this column has no base", suits: ["♠"]  },
    // ---- the Snob family: BIDIRECTIONAL — fires when a matching-suit card lands on
     // this card, AND when this card lands on a matching-suit pile top ----
    { id: "suitSnob", unlock: { type: "behavior", stat: "spadesPlayed", count: 60 }, label: "Spade Snob",  icon: "🧐", kind: "behavior", behavior: "suitSnob", tier: "uncommon", price: 4,
      description: "When a ♠ lands on this card, or this card lands on a ♠ → peek at the next card", suits: ["♠"] },
    // value = coins paid per Heart Snob on the landing card.
    { id: "heartSnob", unlock: { type: "behavior", stat: "heartsPlayed", count: 75 }, label: "Heart Snob",  icon: "💞", kind: "behavior", behavior: "heartSnob", value: 2, tier: "uncommon", price: 2,
      description: "When a ♥ lands on this card, or this card lands on a ♥ → +2 coins", suits: ["♥"] },
    { id: "diamondSnob", unlock: { type: "behavior", stat: "removalsUsed", count: 18 }, label: "Diamond Snob", icon: "💎", kind: "behavior", behavior: "diamondSnob", tier: "uncommon", price: 6,
      description: "When a ♦ lands on this card, or this card lands on a ♦ → shuffle every pile", suits: ["♦"] },
    // digCount = deck cards buried under the pile per Club Snob.
    { id: "clubSnob", unlock: { type: "behavior", stat: "pilesLost", count: 40 }, label: "Club Snob",   icon: "🍀", kind: "behavior", behavior: "clubSnob", digCount: 1, tier: "uncommon", price: 10,
      description: "When a ♣ lands on this card, or this card lands on a ♣ → bury 1 deck card under the pile", suits: ["♣"] },
    // ---- the suit-SYNERGY family: each fires when THIS card lands, scaling
    // by the number of OTHER piles topped by its suit (the landing pile
    // itself never counts). ----
    // value = coins per other ♥-topped pile.
    { id: "heartChoir", unlock: { type: "behavior", stat: "heartsPlayed", count: 200 }, label: "Heart Choir", icon: "💕", kind: "behavior", behavior: "heartChoir", value: 1, tier: "uncommon", price: 3,
      description: "+1 coin per each pile with a ♥ top card", suits: ["♥"] },
    { id: "diamondRipple", unlock: { type: "behavior", stat: "perfectDeals", count: 8 }, label: "Diamond Ripple", icon: "🌊", kind: "behavior", behavior: "diamondRipple", tier: "uncommon", price: 2,
      description: "Shuffle every other pile with a ♦ top card", suits: ["♦"] },
    // RANK ROOTS (renamed from Club Roots, v6.78 — same id, saves bind to
    // it): the trigger is now RANK-match, not ♣-tops. digCount = deck cards
    // buried under each OTHER pile whose top matches this card's rank when
    // it lands (the landing pile itself never counts — the synergy-family
    // rule).
    { id: "clubRoots", unlock: { type: "behavior", stat: "clubsPlayed", count: 120 }, label: "Rank Roots", icon: "🌱", kind: "behavior", behavior: "clubRoots", digCount: 1, tier: "rare", price: 8,
      description: "When this card lands → bury 1 card under each pile whose top card matches this card's rank", suits: ["♣"] },
    { id: "spadeWhispers", unlock: { type: "behavior", stat: "spadesPlayed", count: 200 }, label: "Spade Whispers", icon: "🌬️", kind: "behavior", behavior: "spadeWhispers", tier: "rare", price: 8,
      description: "The next X cards show a hint (higher/lower/same), where X = other piles with a ♠ top card", suits: ["♠"] },
    // step = coins X grows per correct placement (resets to 0 on a wrong one).
    { id: "tell", label: "Tell",        icon: "🔮", kind: "behavior", behavior: "tell", tier: "uncommon", price: 4,
      description: "Shows if the next deck card is higher, lower, or same", suits: ["♠"] },
    // ---- Same-charge / Same-power stickers (fire on correct placement) ----
    { id: "rechargeSameShield", unlock: { type: "behavior", stat: "correctSames", count: 10 }, label: "Recharge Shield", icon: "🛡️", kind: "behavior", behavior: "rechargeSameShield", tier: "rare", price: 8,
      description: "Charge the Same Shield" },
    { id: "activateSamePower", unlock: { type: "behavior", stat: "correctSames", count: 34 }, label: "Tap Power", icon: "🔗", kind: "behavior", behavior: "activateSamePower", tier: "rare", price: 6,
      description: "Fire your Same-Power" },
    // ---- CURSED stickers -----------------------------------------------------
    // cursed: true keeps a sticker OUT of every normal grant pool (store offers,
    // sticker packs, pack-card generation, Mr. Smith's grants, Wild Sticker).
    // Curses are INFLICTED via four pathways, all drawing ONE weighted roll:
    // the mystery "?" node (Just a Two), the Old Joker's PURGE bargain, his
    // DUPLICATE, and the bad TWO DOORS door.
    //   curseWeight  — the roll weight (hand-tune here; bands: mild 6-10,
    //                  medium 5, severe 20 — approved 50/30/20 band split).
    //   curseExclude — pathways this curse can NOT come from:
    //                  "purge" (3 curses at once must not carry item loss),
    //                  "duplicate" (mild-only: the curse is a free card's price),
    //                  "mystery", "doors".
    // price: 0 (never sold).
    { id: "leech",      label: "Leech",       icon: "🪱", kind: "behavior", behavior: "tributeCoin", value: 3, tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. −3 coins" },
    { id: "shrink",     label: "Shrink",      icon: "🪆", kind: "behavior", behavior: "shrink", value: 1, tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. This card counts −1 toward pile size" },
    { id: "mute",       label: "Mute",        icon: "🤐", kind: "behavior", behavior: "mute", tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. While this is a pile's top card, Same cannot be called there" },
    { id: "trapdoor",   label: "Trapdoor",    icon: "🕳", kind: "behavior", behavior: "trapdoor", tier: "common", price: 0, cursed: true, curseWeight: 8,
      description: "Cursed. When it lands, the card at the BOTTOM of the pile returns to the deck" },
    { id: "spoiler",    label: "Spoiler",     icon: "🍂", kind: "behavior", behavior: "spoiler", tier: "common", price: 0, cursed: true, curseWeight: 6,
      description: "Cursed. Reset bonus coins earned this deal to 0" },
    { id: "drainShield", label: "Shield Drain", icon: "🫗", kind: "behavior", behavior: "drainShield", tier: "common", price: 0, cursed: true, curseWeight: 6,
      description: "Cursed. Drain the Same Shield" },
    // ---- medium band: excluded from DUPLICATE (its curse stays mild) --------
    { id: "flatline",   label: "Flatline",    icon: "📉", kind: "behavior", behavior: "flatline", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While this card is a pile's top card, that pile size is 1" },
    { id: "magnet",     label: "Magnet",      icon: "🧲", kind: "behavior", behavior: "magnet", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While this is a pile's top card, your next guess must be played there" },
    { id: "jammer",     label: "Jammer",      icon: "🔇", kind: "behavior", behavior: "jammer", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While this is a pile's top card, the column's Pillar does not work" },
    { id: "peeler",     label: "Peeler",      icon: "🥔", kind: "behavior", behavior: "peeler", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. Any card this card touches loses ALL of its stickers" },
    { id: "drainBase",  label: "Base Drain",  icon: "🪫", kind: "behavior", behavior: "drainBase", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. The column's Base is drained" },
    { id: "malfunction", label: "Malfunction", icon: "💥", kind: "behavior", behavior: "malfunction", chance: 0.1, tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. 10% chance this card kills the pile anyway, even if the guess is correct" },
    // ---- severe: item destruction. NEVER from Purge or Duplicate -----------
    { id: "saboteur",   label: "Saboteur",    icon: "🧨", kind: "behavior", behavior: "saboteur", chance: 0.1, tier: "common", price: 0, cursed: true, curseWeight: 20, curseExclude: ["purge", "duplicate"],
      description: "Cursed. 10% chance the column's Base or Pillar is destroyed" },
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
      kind: "scoring", effect: "suitBounty", suit: "♥", value: 1, tier: "uncommon", price: 5,
      description: "When a ♥ lands in this column → +1 coin" },
    { id: "columnTieSafe", unlock: { type: "behavior", stat: "samesCalled", count: 12 }, label: "Column Tie-Safe", icon: "🛡️",
      kind: "guess", effect: "columnTieSafe", tier: "rare", price: 10,
      description: "Any tie is safe in this column" },
    // value = coins paid when the column is completely WIPED OUT at deal end
    // (the mirror of Guardian). Pays nothing if a single pile survives.
    { id: "lastLicks", unlock: { type: "behavior", stat: "pilesLost", count: 18 }, label: "Last Licks", icon: "🪦",
      kind: "scoring", effect: "columnNoneAlive", value: 3, tier: "uncommon", price: 4,
      description: "At deal end → +3 coins if no pile in this column survived" },
    { id: "columnGuardian", label: "Guardian", icon: "🏛️",
      kind: "scoring", effect: "columnAllAlive", value: 4, tier: "uncommon", price: 4,
      description: "At deal end → +4 coins if every pile in this column survived" },
    // digCount = deck cards buried per qualifying (sticker-free ♣) landing.
    { id: "clubTribute", unlock: { type: "behavior", stat: "clubsPlayed", count: 150 }, label: "Clean Bury", icon: "🧹",
      kind: "composition", effect: "clubTribute", digCount: 1, tier: "rare", price: 10,
      description: "When a ♣ with no stickers lands in this column → bury 1 card under that pile" },
    { id: "allHeartsCoin", unlock: { type: "milestone", stat: "coinsEarnedLifetime", count: 60 }, label: "All Hearts", icon: "💗",
      kind: "scoring", effect: "allSuitTop", suit: "♥", value: 4, tier: "common", price: 4,
      description: "At deal end → +4 coins if every surviving pile in this column has a ♥ top card" },
    // value = coins per alive ♥-topped pile in this column at end of deal.
    { id: "envy", unlock: { type: "milestone", stat: "runsPlayed", count: 5 }, label: "Envy", icon: "💚",
      kind: "scoring", effect: "heartPiles", value: 2, tier: "common", price: 4,
      description: "At deal end → +2 coins per pile in this column with a ♥ top card" },
    // threshold = the in-column streak step the bonus starts at (+1 size per
    // step from there on; resets on a wrong guess or any other-column guess).
    { id: "streakBank", unlock: { type: "behavior", stat: "perfectDeals", count: 2 }, label: "Streak Size", icon: "🏦",
      kind: "modifier", effect: "streakSize", threshold: 3, tier: "rare", price: 4,
      description: "From the 3rd consecutive correct guess in this column → +1 pile size per guess. Resets on a wrong guess or any guess in another column" },
    // threshold = the streak step burials start at; digCount = cards buried
    // per correct in-column guess from that step onward (flat, no escalation).
    { id: "streakTribute", unlock: { type: "behavior", stat: "cardsBuried", count: 90 }, label: "Streak Bury", icon: "🔥",
      kind: "composition", effect: "streakTribute", threshold: 4, digCount: 1, tier: "rare", price: 10,
      description: "From the 4th consecutive correct guess in this column → bury 1 card per guess. Resets on a wrong guess or any guess in another column" },
    // value = the CAP this column may be widened to. The board's normal 3-way
    // split runs first, then this column gains ONE seat, never past `value` —
    // so a 1-pile column opens with 2 and a column already at the cap is
    // untouched. Ditto mirroring this widens the mirroring column too.
    { id: "fourthSeat", unlock: { type: "milestone", stat: "endlessStagesReached", count: 1 }, label: "Fourth Seat", icon: "🪑",
      kind: "composition", effect: "columnPiles", value: 4, tier: "rare", price: 10,
      description: "This column starts the deal with 1 extra pile (up to 4)" },
    { id: "secondWind", label: "Second Wind", icon: "🌬️",
      kind: "guess", effect: "secondWind", tier: "rare", price: 6, saveChance: 0.25,
      description: "Each pile that dies in this column has a 25% chance to be saved, but all the buried cards return to the deck" },
    { id: "greedy", unlock: { type: "milestone", stat: "dealsSurvived", count: 6 }, label: "Greedy", icon: "🤑",
      kind: "scoring", effect: "greedy", value: 4, tier: "common", price: 5,
      description: "At deal end → +4 coins if this is the only equipped pillar" },
    { id: "highestEven", unlock: { type: "milestone", stat: "bestCampaignScore", count: 220 }, label: "Highest Heart", icon: "💗",
      kind: "scoring", effect: "highestHeart", tier: "rare", price: 8,
      description: "At deal end → earn coins equal to the highest numbered ♥ top card in this column (2–10 face value, Ace pays 1, royals pay 0)" },
    // minStickers = stickers a landing ♣ must carry; digCount = cards buried.
    { id: "denseBury", unlock: { type: "behavior", stat: "stickersApplied", count: 140 }, label: "Dense Bury", icon: "🧊",
      kind: "composition", effect: "denseBury", minStickers: 2, digCount: 1, tier: "rare", price: 10,
      description: "When a ♣ with 2+ stickers lands correctly in this column → bury 1 card under that pile" },
    // trigger = the pile size (cards) that arms the one-shot revive offer.
    { id: "revive", unlock: { type: "milestone", stat: "dealsWonLegendary", count: 4 }, label: "Revive", icon: "♻️",
      kind: "guess", effect: "revive", trigger: 10, tier: "rare", price: 10,
      description: "When a pile in this column reaches 10 cards → revive one dead pile" },
    // BULK RATE: the store's Purge ladder climbs `value` less per purchase
    // while equipped (a step of 2 becomes 1). Pure derived pricing — no
    // saved state of its own.
    { id: "bulkRate", unlock: { type: "behavior", stat: "removalsUsed", count: 16 }, label: "Bulk Rate", icon: "🏷️",
      kind: "meta", effect: "purgeStepDiscount", value: 1, tier: "uncommon", price: 6,
      description: "The store's Purge price climbs by 1 instead of 2. No effect during deal" },
    // FREEBIE: one random shelf item per store visit costs 0 — rolled from
    // the same seeded store stream, so a reload shows the same gift.
    { id: "freebie", unlock: { type: "behavior", stat: "pinkyTipsSeen", count: 2 }, label: "Freebie", icon: "🎁",
      kind: "meta", effect: "freebie", tier: "rare", price: 9,
      description: "One random item in every store costs 0 coins. No effect during deal" },
    // RARE HUNTER: the store's rare tier weight is multiplied by `value`
    // while equipped (20 → 40 against common 100 / uncommon 50).
    { id: "rareHunter", unlock: { type: "behavior", stat: "pillarsPlaced", count: 25 }, label: "Rare Hunter", icon: "🦅",
      kind: "meta", effect: "rareHunter", value: 2, tier: "rare", price: 8,
      description: "Rare items appear in the store twice as often. No effect during deal" },
    // BOUNCER: a campaign-level ward — 30% to turn JUST A TWO away at a ?
    // node. He still appears, says "Ah, nothing for you today.", and takes
    // nothing. No in-deal effect at all; the engine never sees it.
    { id: "twoWard", unlock: { type: "behavior", stat: "jokersPlayed", count: 4 }, label: "Bouncer", icon: "🚪",
      kind: "meta", effect: "twoWard", chance: 0.3, tier: "uncommon", price: 5,
      description: "30% chance to turn away a Just a Two mystery outcome. No effect during deal" },
    // FLYPAPER: sticky column — a small chance each landing picks up a
    // random sticker, permanently.
    { id: "flypaper", unlock: { type: "behavior", stat: "stickersApplied", count: 25 }, label: "Flypaper", icon: "🪤",
      kind: "live", effect: "flypaper", chance: 0.05, tier: "uncommon", price: 6,
      description: "When a card lands correctly in this column → 5% chance it gains a random sticker" },
    // {rank} pillars: the rank locks the FIRST time the pillar shows in a
    // shop this climb — Underdog reads your deck's SCARCEST rank, Crowd
    // Favorite its most common (random tiebreak) — and holds all climb.
    { id: "underdog", unlock: { type: "behavior", stat: "cardsBuried", count: 40 }, label: "Underdog", icon: "🐜",
      kind: "composition", effect: "rankBury", digCount: 1, tier: "rare", price: 6,
      description: "When a {rank} lands correctly in this column → bury 1 deck card under that pile" },
    { id: "crowdFavorite", unlock: { type: "milestone", stat: "dealsSurvived", count: 18 }, label: "Crowd Favorite", icon: "📣",
      kind: "live", effect: "rankCoin", value: 2, tier: "rare", price: 6,
      description: "When a {rank} lands correctly in this column → +2 coins" },
    // ---- expansion Pillars ------------------------------------------------
    { id: "insurance", unlock: { type: "behavior", stat: "pilesLost", count: 55 }, label: "Insurance", icon: "🛟",
      kind: "scoring", effect: "insurance", value: 8, tier: "rare", price: 4,
      description: "At deal end → +8 coins if only one pile is alive" },
    { id: "ditto", unlock: { type: "milestone", stat: "runsWon", count: 1 }, label: "Ditto", icon: "🪞",
      kind: "meta", effect: "ditto", tier: "rare", price: 5,
      description: "Mirrors the center column's pillar" },
    // value = extra pile size per ♦ card (top or buried) in the column.
    { id: "stickerCount", label: "Massive Diamond", icon: "🏷️",
      kind: "modifier", effect: "heavyDiamond", value: 2, tier: "uncommon", price: 4,
      description: "♦ cards in this column count as +2 toward pile size" },
    // value = coins per prime-rank (2/3/5/7) card landing correctly here.
    { id: "prime", unlock: { type: "milestone", stat: "bossesBeaten", count: 20 }, label: "Prime", icon: "🔢",
      kind: "live", effect: "prime", value: 1, tier: "rare", price: 3,
      description: "When a prime-rank card (2/3/5/7) lands correctly in this column → +1 coin" },
    { id: "queensEye", label: "Queen's Eye", icon: "👁️",
      kind: "live", effect: "queensEye", tier: "uncommon", price: 4,
      description: "When a royal ♠ (J/Q/K) lands in this column → peek at the next card" },
    { id: "royalCourt", label: "Shuffler", icon: "👑",
      kind: "guess", effect: "shuffler", tier: "uncommon", price: 3,
      description: "When a ♦ lands in this column → shuffle the other piles in this column" },
    // value = coins per buried card in the largest ♥-topped alive pile.
    { id: "excavator", unlock: { type: "behavior", stat: "cardsBuried", count: 60 }, label: "Excavator", icon: "⛏️",
      kind: "scoring", effect: "excavator", value: 1, tier: "uncommon", price: 3,
      description: "At deal end → +1 coin per buried card in this column's largest pile with a ♥ top card" },
    // chance = probability (0–1) the flip pays `value` (no suit requirement).
    { id: "gambler", unlock: { type: "behavior", stat: "jokersPlayed", count: 12 }, label: "Gambler", icon: "🎲",
      kind: "scoring", effect: "gambler", value: 3, chance: 0.5, tier: "uncommon", price: 5,
      description: "At deal end → 50/50: +3 coins or nothing" },
    { id: "lastRites", unlock: { type: "behavior", stat: "dealsWonLegendary", count: 1 }, label: "Last Rites", icon: "🕯️",
      kind: "live", effect: "lastRites", tier: "rare", price: 10,
      description: "When a pile in this column dies → peek the next card" },
    // selfDestruct = probability (0–1) the Pillar destroys itself each deal end.
    // chance = probability the ♠ landing actually fires the peek.
    { id: "static", unlock: { type: "behavior", stat: "zenMediumWon", count: 2 }, label: "Static", icon: "🔌",
      kind: "live", effect: "static", chance: 0.5, tier: "rare", price: 3,
      description: "When a ♠ lands in this column → 50% chance to peek at the next card" },
    { id: "wildAces", unlock: { type: "behavior", stat: "jokersPlayed", count: 8 }, label: "Wild Aces", icon: "🃏",
      kind: "guess", effect: "wildAces", tier: "rare", price: 10,
      description: "Aces count as high or low in this column" },
    { id: "diamondAnchor", unlock: { type: "behavior", stat: "diamondsPlayed", count: 200 }, label: "Diamond Anchor", icon: "⚓",
      kind: "modifier", effect: "diamondAnchor", tier: "rare", price: 6,
      description: "At deal end → exclude any pile in this column with a ♦ top card from the smallest-pile score" },
    { id: "diamondDistribution", unlock: { type: "behavior", stat: "removalsUsed", count: 10 }, label: "Diamond Distribution", icon: "⚖️",
      kind: "guess", effect: "diamondDistribution", tier: "uncommon", price: 3,
      description: "When a ♦ lands in this column → make all piles in this column equal size" },

    /* ====================== ARCHETYPE BATCH v6.76 =======================
       Engine-implemented since v6.76. GATING (v6.80, user-approved): the
       simple/early/mid items ship UNGATED as starting items; the mid-late
       and late ARCHETYPE ANCHORS carry `unlock` gates below. Every price
       is an R4 PROPOSAL, marked TUNE. */

    // ---- Deck-composition Pillars — every condition below evaluates against
    //      the FULL deck (board + buried + remaining), LIVE, at each landing.
    // EMPTY RANKS: the bury count is DERIVED — 1 card per rank that has zero
    // copies anywhere in the full deck — so there is no count knob.
    // TUNE: price 8 proposed (R4).
    { id: "zeroRanksBury", unlock: { type: "behavior", stat: "removalsUsed", count: 40 }, label: "Empty Ranks", icon: "🈳",
      kind: "live", effect: "clubZeroRanksBury", tier: "rare", price: 8,
      description: "When a ♣ lands in this column → bury 1 card under that pile per rank with zero copies in your full deck" },
    // CRAZY EIGHTS: a composition condition (8s the most common rank in the
    // full deck) changes the column's STARTING pile size. The target size 8
    // is the mechanic itself — no knob.
    // TUNE: price 10 proposed (R4); deliberately huge vs normal starting size — flagged for balance.
    { id: "eightStart", unlock: { type: "behavior", stat: "perfectDeals", count: 12 }, label: "Crazy Eights", icon: "8️⃣",
      kind: "composition", effect: "startPileSizeEight", tier: "rare", price: 10,
      description: "If 8s are the most common rank in your full deck → this column's piles start at pile size 8" },
    // ROYAL SANCTUARY: composition-gated guess safety — the no-2s condition
    // is the whole knob.
    // TUNE: price 6 proposed (R4).
    { id: "royalSanctuary", unlock: { type: "behavior", stat: "removalsUsed", count: 30 }, label: "Royal Sanctuary", icon: "🏰",
      kind: "guess", effect: "royalSafeNoTwos", tier: "uncommon", price: 6,
      description: "If your full deck contains no 2s → royals (J/Q/K) are always safe in this column" },
    // VOID TRIBUTE: {suit} pillar — the suit locks the FIRST time the pillar
    // shows in a shop this climb and holds all climb (shopRoll: "suit").
    // buryCount = cards buried per qualifying ♣ landing.
    // TUNE: price 8 proposed (R4).
    { id: "absentSuitClubBury", unlock: { type: "behavior", stat: "clubsPlayed", count: 200 }, label: "Void Tribute", icon: "🌫️",
      kind: "live", effect: "absentSuitClubBury", shopRoll: "suit", buryCount: 2, tier: "rare", price: 8,
      description: "If your full deck contains no {suit} → when a ♣ lands in this column, bury 2 cards under that pile" },
    // MAJORITY RULE: {suit} pillar (shopRoll: "suit", same first-shop lock).
    // The 50% majority threshold is the mechanic itself — no knob.
    // TUNE: price 8 proposed (R4).
    { id: "suitMajoritySafe", unlock: { type: "milestone", stat: "bossesBeaten", count: 6 }, label: "Majority Rule", icon: "🗳️",
      kind: "guess", effect: "suitMajoritySafe", shopRoll: "suit", tier: "rare", price: 8,
      description: "If half or more of your full deck is {suit} → {suit} cards are safe when they land in this column" },
    // DIAMOND ECHO: the size bonus is DERIVED — +1 per duplicate of the
    // landing card's rank in the full deck — so there is no count knob.
    // TUNE: price 6 proposed (R4).
    { id: "diamondDupeSize", unlock: { type: "behavior", stat: "diamondsPlayed", count: 150 }, label: "Diamond Echo", icon: "👯",
      kind: "live", effect: "diamondDupeSize", tier: "uncommon", price: 6,
      description: "When a ♦ lands in this column → +1 pile size per duplicate of that card's rank in your full deck" },

    // ---- SAME-TOLERANCE family (family: "sameTolerance") -----------------
    // Four relaxations of what survives a SAME call in this column; `tol`
    // selects the rule. ONE same-tolerance pillar per column MAX, enforced
    // at placement (engine work to come — the data carries the family tag
    // now). Every description states the family rule: a survived Same counts
    // as a FULL correct Same — it charges the Same Shield and fires the
    // equipped Same-Power.
    // TUNE: price 9 proposed (R4).
    { id: "sameTolNear", unlock: { type: "behavior", stat: "correctSames", count: 52 }, label: "Close Call", icon: "🤏",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "near", tier: "rare", price: 9,
      description: "Same calls are safe on cards ±1 in value in this column. A survived Same counts as a full correct Same — charges the Same Shield and fires your Same-Power" },
    // TUNE: price 7 proposed (R4).
    { id: "sameTolRoyal", unlock: { type: "behavior", stat: "samesCalled", count: 40 }, label: "Royal Pair", icon: "🤴",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "royalPair", tier: "uncommon", price: 7,
      description: "A royal landing on a royal survives a Same call in this column. A survived Same counts as a full correct Same — charges the Same Shield and fires your Same-Power" },
    // TUNE: price 7 proposed (R4).
    { id: "sameTolSum10", label: "Perfect Ten", icon: "🔟",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "sum10", tier: "uncommon", price: 7,
      description: "Ranks summing to 10 survive a Same call in this column. A survived Same counts as a full correct Same — charges the Same Shield and fires your Same-Power" },
    // TUNE: price 6 proposed (R4).
    { id: "sameTolSuit", label: "Suit Match", icon: "🧥",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "sameSuit", tier: "uncommon", price: 6,
      description: "A suit landing on its own suit is safe in this column, including Same calls. A survived Same counts as a full correct Same — charges the Same Shield and fires your Same-Power" },

    // ---- SHIELDS ----------------------------------------------------------
    // RANK SHIELD (dynamic, v6.78): at the START of each deal the shield
    // re-reads your FULL deck and protects its most common rank. Tie rule:
    // the INCUMBENT (the rank that's been most common longest) keeps the
    // shield until strictly surpassed; a tie with no incumbent picks
    // randomly (deal-seeded). The current rank shows on the plaque and in
    // the {rank} template below.
    // TUNE: price 5 proposed (R4).
    { id: "rankShield", label: "Rank Shield", icon: "🔰",
      kind: "guess", effect: "rankShield", tier: "uncommon", price: 5,
      description: "Most common card in deck ({rank}) is always safe in this column" },
    // SCARCE SUIT (v6.81, was "Daily Suit"): no roll any more — each deal
    // start reads the FULL deck and shields the suit it holds the FEWEST of
    // (among suits present; ties break by canonical suit order). The id and
    // the effect key are STABLE ("suitShield"/"suitShieldDaily" — saves and
    // engine hooks bind to them); only the player-facing label moved.
    // TUNE: price 6 proposed (R4).
    { id: "suitShield", label: "Scarce Suit", icon: "📉",
      kind: "guess", effect: "suitShieldDaily", tier: "uncommon", price: 6,
      description: "The suit your deck holds the fewest of is safe when it lands in this column. Rechecked at the start of each deal, shown on the plaque" },

    // ---- ECONOMY / STORE --------------------------------------------------
    // FLAT PURGE: value = the fixed Purge price while equipped (overrides the
    // climbing ladder). Pure derived pricing — no saved state of its own.
    // TUNE: price 8 proposed (R4).
    { id: "purgeFlatFive", label: "Flat Purge", icon: "✋",
      kind: "meta", effect: "purgeFlat", value: 5, tier: "rare", price: 8,
      description: "The store's Purge always costs 5 coins. No effect during deal" },
    // ON THE HOUSE: covers the FIRST restock per store visit AND the FIRST
    // reshuffle per deal. No knobs — the two freebies are the mechanic.
    // TUNE: price 7 proposed (R4).
    { id: "firstFree", label: "On the House", icon: "🆓",
      kind: "meta", effect: "firstFree", tier: "rare", price: 7,
      description: "The first restock in each store and the first reshuffle of each deal are free" },
    // EIGHT BALL: a plain peek trigger on an 8 landing. No knobs.
    // TUNE: price 3 proposed (R4).
    { id: "eightPeek", label: "Eight Ball", icon: "🎱",
      kind: "live", effect: "eightPeek", tier: "common", price: 3,
      description: "When an 8 lands in this column → peek at the next card" },

    // ---- PAUPER family -----------------------------------------------------
    // PAUPER: all four gate on a LIGHT purse — purseBelow = the exclusive
    // coin ceiling, evaluated LIVE at every landing (drop below it mid-deal
    // and the pillar wakes; climb back above and it sleeps). Common + cheap
    // by design: the broke player's comeback kit.
    // value = coins paid per qualifying ♥ landing.
    // TUNE: price 2 proposed (R4).
    { id: "pauperHeart", label: "Pauper's Heart", icon: "❤️‍🩹",
      kind: "live", effect: "pauperHeart", purseBelow: 10, value: 3, tier: "common", price: 2,
      description: "While your purse holds under 10 coins → when a ♥ lands in this column, +3 coins" },
    // value = the pile size a ♦ counts toward (board-wide) while broke,
    // replacing the normal +1.
    // TUNE: price 3 proposed (R4).
    { id: "pauperDiamond", label: "Pauper's Diamond", icon: "💎",
      kind: "live", effect: "pauperDiamondSize", purseBelow: 10, value: 2, tier: "common", price: 3,
      description: "While your purse holds under 10 coins → a ♦ landing anywhere on the board counts +2 toward pile size instead of +1" },
    // No knobs — the tell (higher/lower/same) is the mechanic.
    // TUNE: price 2 proposed (R4).
    { id: "pauperSpade", label: "Pauper's Spade", icon: "🥄",
      kind: "live", effect: "pauperSpadeTell", purseBelow: 10, tier: "common", price: 2,
      description: "While your purse holds under 10 coins → when a ♠ lands in this column, the next card shows a tell (higher/lower/same)" },
    // digCount = cards buried per qualifying ♣ landing.
    // TUNE: price 2 proposed (R4).
    { id: "pauperClub", label: "Pauper's Club", icon: "🍀",
      kind: "live", effect: "pauperClubBury", purseBelow: 10, digCount: 1, tier: "common", price: 2,
      description: "While your purse holds under 10 coins → when a ♣ lands in this column, bury 1 card under that pile" },

    // ---- CURSE + THINNING ---------------------------------------------------
    // CURSE HARVEST: turns a cursed landing into value. digCount = cards
    // buried per cursed landing; the peek after is fixed (the mechanic).
    // TUNE: price 7 proposed (R4).
    { id: "curseHarvest", label: "Curse Harvest", icon: "🧺",
      kind: "live", effect: "curseBuryPeek", digCount: 1, tier: "rare", price: 7,
      description: "When a cursed card lands in this column → bury 1 card under that pile, then peek at the next card" },
    // CLUB THIN: per = the deck-remaining step the bury scales on;
    // digCount = cards buried per full step.
    // TUNE: price 6 proposed (R4).
    { id: "clubThin", unlock: { type: "behavior", stat: "cardsBuried", count: 150 }, label: "Club Thin", icon: "✂️",
      kind: "live", effect: "clubThin", per: 25, digCount: 1, tier: "uncommon", price: 6,
      description: "When a ♣ lands in this column → bury 1 card per 25 cards remaining in the deck" },
    // RANK PURGE: an ON-PURCHASE purge — {rank} rolls the first time the
    // pillar shows in a shop this climb (shopRoll: "rank"), is shown before
    // purchase, and every copy leaves the deck at buy time. Fires once, at
    // the shop; nothing in-deal.
    // Price 10 is USER-SPECIFIED (not an R4 proposal).
    { id: "purgeRank", label: "Rank Purge", icon: "🗑️",
      kind: "meta", effect: "purgeRank", shopRoll: "rank", tier: "rare", price: 10,
      description: "On purchase → purge every {rank} from your deck. No effect during deal" },

    // SIZE-ONE DIAMONDS (archetype batch v6.76 — ungated, data only):
    // value = the pile size a ♦ counts toward (board-wide) while the column
    // holds a size-1 pile, replacing the normal +1.
    // TUNE: price 5 proposed (R4).
    { id: "sizeOneDiamonds", label: "Diamond Lifeline", icon: "🔷",
      kind: "live", effect: "sizeOneDiamonds", value: 2, tier: "uncommon", price: 5,
      description: "While any pile in this column has pile size 1 → a ♦ landing anywhere on the board counts +2 toward pile size instead of +1" },
  ],

  /* --------------------------------------------------------------------
     BASES — column artifacts bound to the BOTTOM of a column. ACTIVE,
     once-per-deal powers: they charge each deal, fire once when tapped,
     and stay spent until the next deal. `target: "pile"` means
     the player picks a target pile. `digCount`/`peekCount`/`coinPerPile`/
     `coinPerCard`/`buryPerSticker`/`reward` are effect knobs.
  -------------------------------------------------------------------- */
  bases: [
    // peekCount = upcoming cards peeked after the sacrifice.
    { id: "kamikaze", unlock: { type: "milestone", stat: "dealsWonLegendary", count: 2 }, label: "Kamikaze", icon: "💥",
      kind: "active", effect: "kamikaze", peekCount: 2, tier: "rare", price: 8,
      description: "Kill a random ♠-topped pile in this column, → peek the next 2 cards" },
    { id: "spadePeek", unlock: { type: "behavior", stat: "zenHardWon", count: 1 }, label: "Spade Peeker", icon: "🔦",
      kind: "active", effect: "spadePeek", tier: "uncommon", price: 7,
      description: "Peek the next card. Requires every pile in this column has a ♠ on top" },
    { id: "shuffleColumn", label: "Upheaval", icon: "🌀",
      kind: "active", effect: "shuffleColumn", tier: "common", price: 5,
      description: "Shuffle every pile in this column" },
    { id: "revive", label: "Phoenix", icon: "🔥",
      kind: "active", effect: "reviveBase", tier: "uncommon", price: 7,
      description: "Revive a random dead pile in this column. Buried cards return to the deck" },
    { id: "randomSticker", unlock: { type: "behavior", stat: "stickersApplied", count: 30 }, label: "Wild Sticker", icon: "🎲",
      kind: "active", effect: "randomSticker", tier: "uncommon", price: 10,
      description: "Apply a random sticker to a random top card in this column" },
    { id: "evenOut", label: "Ballast", icon: "🪨",
      kind: "active", effect: "evenOut", tier: "common", price: 5,
      description: "Make all piles in this column equal size" },
    { id: "setValue", unlock: { type: "milestone", stat: "runsWon", count: 2 }, label: "Rank Setter", icon: "🗿",
      kind: "active", effect: "setValue", tier: "rare", price: 10,
      description: "Permanently set every top card's rank in this column to the bottom pile's rank" },
    { id: "setSuit", unlock: { type: "milestone", stat: "runsWon", count: 3 }, label: "Suit Setter", icon: "🎨",
      kind: "active", effect: "setSuit", tier: "rare", price: 5,
      description: "Permanently set every top card's suit in this column to the bottom pile's suit" },
    // buryPerSticker = deck cards buried per sticker peeled off the pile card.
    { id: "stickerHarvest", unlock: { type: "behavior", stat: "stickersApplied", count: 115 }, label: "Sticker Harvest", icon: "🌾",
      kind: "active", effect: "stickerHarvest", target: "pile", buryPerSticker: 2, tier: "uncommon", price: 6,
      description: "Choose a pile → bury 2 cards per sticker on its top card, then peel all those stickers" },
    { id: "refreshBases", unlock: { type: "behavior", stat: "basesPlaced", count: 25 }, label: "Reactor", icon: "⚛️",
      kind: "active", effect: "refreshBases", tier: "rare", price: 9,
      description: "Recharge your other two bases" },
    // ---- expansion Bases --------------------------------------------------
    // digCount = cards buried under each matching-suit-topped pile.
    { id: "clubDig", unlock: { type: "behavior", stat: "clubsPlayed", count: 250 }, label: "Club Dig", icon: "♣️",
      kind: "active", effect: "suitDig", suit: "♣", digCount: 1, tier: "rare", price: 8,
      description: "Bury 1 card under each ♣-topped pile in this column" },
    // peekCount = upcoming cards peeked after the demolition. Destroys THIS
    // column's pillar; with no pillar here the base stays yellow.
    { id: "demolish", unlock: { type: "behavior", stat: "pillarsPlaced", count: 18 }, label: "Demolish", icon: "🔨",
      kind: "active", effect: "demolish", peekCount: 3, tier: "uncommon", price: 8,
      description: "Destroy this column's pillar permanently, then peek the next 3 cards" },
    // coinPerPile = coins gained per ♥-topped pile destroyed.
    { id: "heartDemolish", unlock: { type: "behavior", stat: "heartsPlayed", count: 90 }, label: "Heart Demolish", icon: "💔",
      kind: "active", effect: "heartDemolish", coinPerPile: 4, tier: "uncommon", price: 5,
      description: "Destroy every ♥-topped pile in this column. +4 coins per pile destroyed" },
    // coinPerCard = coins gained per ♥ card counted in the column.
    { id: "tax", label: "Heart Tax", icon: "🧾",
      kind: "active", effect: "tax", suit: "♥", coinPerCard: 1, tier: "uncommon", price: 5,
      description: "+1 coin per ♥ card in this column" },
    // ---- Same-charge / Same-power bases (activated, once per deal) ----
    { id: "rechargeSame", unlock: { type: "milestone", stat: "correctSames", count: 28 }, label: "Recharge Cell", icon: "🔋",
      kind: "active", effect: "rechargeSameShield", tier: "rare", price: 10,
      description: "Charge the Same Shield" },
    { id: "activateSame", unlock: { type: "behavior", stat: "correctSames", count: 44 }, label: "Power Surge", icon: "⚡",
      kind: "active", effect: "activateSamePower", tier: "rare", price: 10,
      description: "Activate your Same-Power" },
    // LAST RESORT: the panic button — bury the WHOLE remaining deck under
    // one pile here and the deal ends as a win, scored normally. Never in a
    // boss deal. It blows itself up AND any base beside it on use.
    { id: "lastResort", unlock: { type: "behavior", stat: "pilesLost", count: 75 }, label: "Last Resort", icon: "🧨",
      kind: "active", effect: "lastResort", tier: "rare", price: 10,
      description: "In a non-boss deal, bury the whole deck under a pile in this column and win instantly. Any Base nearby is destroyed" },
    // EMPTY PURSE: every coin you hold, for peeks — 1 baseline + 1 more per
    // 10 coins spent (v6.74 rework; was a flat single peek).
    { id: "emptyPurse", unlock: { type: "milestone", stat: "coinsEarnedLifetime", count: 150 }, label: "Empty Purse", icon: "👛",
      kind: "active", effect: "emptyPurse", tier: "rare", price: 5,
      description: "Spend ALL your coins → peek 1 card, +1 more per 10 coins spent" },
    // SAME TELL: answers exactly one question — is the next card the same
    // rank as a top card ANYWHERE on the board? A match gets the = mark;
    // no match, no word. (v6.62: board-wide, was this-column-only.)
    { id: "sameTell", label: "Same Tell", icon: "🪞",
      kind: "active", effect: "sameTell", tier: "uncommon", price: 5,
      description: "If the next card is the SAME rank as a top card anywhere on the board, the = mark appears on that card" },
    // LONE EYE: the no-Same-Power build's consolation — a plain peek that
    // only works while the Same slot stays EMPTY.
    { id: "lonePeek", unlock: { type: "behavior", stat: "samesCalled", count: 8 }, label: "Lone Eye", icon: "👁",
      kind: "active", effect: "lonePeek", tier: "rare", price: 10,
      description: "Peek the next card. Only works while no Same-Power is equipped" },
    // CLUB ORACLE: reads the next card against EVERY ♣ top in its column.
    { id: "clubOracle", unlock: { type: "behavior", stat: "clubsPlayed", count: 90 }, label: "Club Oracle", icon: "🔮",
      kind: "active", effect: "clubTell", tier: "uncommon", price: 8,
      description: "Put a tell marker on each ♣-topped pile in this column for the next draw. Tell marker shows if the next card is higher, lower, or same" },
    // AMBUSH ONLY. Its light is green during an ambush and red every other
    // deal — it is a panic button you carry for the deals you did not choose.
    { id: "ambushOut", unlock: { type: "behavior", stat: "ambushesWon", count: 3 }, label: "Escape Hatch", icon: "🚪",
      kind: "active", effect: "ambushWin", tier: "rare", price: 8,
      description: "Only usable in an ambush from Just a Two → clear the deal instantly" },

    /* ====================== ARCHETYPE BATCH v6.76 =======================
       Engine-implemented since v6.76. GATING (v6.80): early/mid bases ship
       UNGATED except Purge Coupon; the anchors (Transmute, Chorus) gate.
       Every price is an R4 PROPOSAL, marked TUNE. */

    // PURGE COUPON: value = coins knocked off the store's Purge price per
    // activation; min = the floor the price never drops below. A store-side
    // lever carried on a base — nothing happens in-deal.
    // TUNE: price 5 proposed (R4).
    { id: "purgeDiscount", unlock: { type: "behavior", stat: "removalsUsed", count: 3 }, label: "Purge Coupon", icon: "🎟️",
      kind: "active", effect: "purgeDiscount", value: 3, min: 5, tier: "uncommon", price: 5,
      description: "Reduce the cost of the Store's Purge" },
    // TRANSMUTE: an ON-PURCHASE base — it fires at BUY time and never in a
    // deal. Its target {rank} is DERIVED LIVE — the rank your full deck
    // holds the most copies of at buy time (ties → lowest; recomputed for
    // every display, so the shelf always names the current leader). Only
    // the {suit} rolls at the store (shopRoll, first shelf appearance this
    // climb, shown before purchase).
    // TUNE: price 8 proposed (R4).
    { id: "transmute", unlock: { type: "milestone", stat: "bossesBeaten", count: 8 }, label: "Transmute", icon: "⚗️",
      kind: "active", effect: "transmute", shopRoll: "suit", tier: "rare", price: 8,
      description: "Change all {rank}s to {suit}" },
    // SACRIFICE: target: "pile" — the player picks the pile whose top card
    // is purged from the deck; the pile then dies. Thinning at a blood price.
    // TUNE: price 6 proposed (R4).
    { id: "sacrifice", label: "Sacrifice", icon: "🩸",
      kind: "active", effect: "sacrifice", target: "pile", tier: "uncommon", price: 6,
      description: "Choose a pile → purge its top card from your deck, then kill that pile" },
    // DEVIL'S DEAL: doubles run.bonusCoins (this deal's bonus tally), then
    // inflicts a curse on a top card in this column. No knobs — the trade is
    // the mechanic.
    // TUNE: price 8 proposed (R4).
    { id: "devilsDeal", label: "Devil's Deal", icon: "😈",
      kind: "active", effect: "devilsDeal", tier: "rare", price: 8,
      description: "Double your bonus coins earned this deal, then add a curse to a top card in this column" },
    // CLEANSE: strips every curse off this column's top cards. No knobs.
    // TUNE: price 5 proposed (R4).
    { id: "cleanseColumn", label: "Cleanse", icon: "🧼",
      kind: "active", effect: "cleanseColumn", tier: "uncommon", price: 5,
      description: "Remove all curses from the top cards in this column" },
    // CHORUS: the target rank is DERIVED — the rank your full deck holds the
    // most copies of — so there is no rank knob.
    // TUNE: price 8 proposed (R4).
    { id: "chorus", unlock: { type: "milestone", stat: "bestCampaignScore", count: 160 }, label: "Chorus", icon: "🎼",
      kind: "active", effect: "chorus", tier: "rare", price: 8,
      description: "Set every top card in this column to the rank your full deck holds the most copies of" },
    // DIAMOND BOOST (v6.78: column-wide, no target pick) — value = the pile
    // size added to EVERY ♦-topped pile in the column.
    // TUNE: price 3 proposed (R4).
    { id: "diamondBoost", label: "Diamond Boost", icon: "💠",
      kind: "active", effect: "diamondBoost", value: 3, tier: "common", price: 3,
      description: "Every pile with a ♦ top card in this column → +3 pile size" },
  ],

  /* --------------------------------------------------------------------
     SAME-POWERS — the artifact class a correct Same triggers. Exactly ONE
     is equipped at a time; every power acts on the piles DIRECTLY linked
     (via the synapse network) to the pile the Same was called on.
     `value` is the per-link coefficient (cards buried / coins / size).
  -------------------------------------------------------------------- */
  samePowers: [
    // value = cards buried under EACH directly-linked alive pile.
    { id: "linkBury", unlock: { type: "behavior", stat: "samesCalled", count: 30 }, label: "Burrow", icon: "🦫",
      effect: "linkBury", value: 1, tier: "rare", price: 9,
      // {suit} is the climb-fixed rolled suit (native substitutes it live).
      description: "Bury 1 card under every pile with a {suit} top card" },
    { id: "linkRevive", unlock: { type: "behavior", stat: "correctSames", count: 24 }, label: "Rekindle", icon: "🌱",
      effect: "linkRevive", tier: "rare", price: 9,
      description: "Revive a dead pile" },
    // value = coins per alive pile on the board (board-wide, not just linked).
    { id: "linkCoins", label: "Dividend", icon: "💰",
      effect: "linkCoins", value: 1, tier: "rare", price: 9,
      description: "Gain 1 coin for each alive pile" },
    { id: "linkShuffle", label: "Link Shuffler", icon: "🔀",
      effect: "linkShuffle", tier: "rare", price: 9,
      description: "Shuffle every alive pile" },
    { id: "samePeek", label: "Same Peeker", icon: "👁️",
      effect: "samePeek", tier: "rare", price: 9,
      description: "Peek the next card" },
    // SECOND SIGHT (v6.78): ONE draw of total vision — every alive pile
    // shows its tell (higher/lower/same) for the next draw only, then the
    // draw consumes them all (the Club Oracle window mechanic, board-wide).
    { id: "linkTell", unlock: { type: "behavior", stat: "correctSames", count: 16 }, label: "Second Sight", icon: "🔮",
      effect: "linkTell", tier: "rare", price: 9,
      description: "Every alive pile shows a tell (higher/lower/same) for the next draw" },
    // Sprays the CALLED pile's whole column. Each sticker is rolled from the
    // grantable pool and is PERMANENT — it stays on the card after the deal.
    { id: "linkSticker", unlock: { type: "behavior", stat: "stickersApplied", count: 70 }, label: "Sticker Spray", icon: "🎨",
      effect: "linkSticker", tier: "rare", price: 9,
      description: "Apply a random sticker to every top card in this column" },
    // chance = probability (0–1) that a card is purged from the REMAINING deck
    // — it never touches the board, only what is still to come.
    { id: "linkPurge", unlock: { type: "behavior", stat: "removalsUsed", count: 14 }, label: "Long Odds", icon: "🎯",
      effect: "linkPurge", chance: 0.25, tier: "rare", price: 9,
      description: "25% chance to permanently purge a card from the deck" },
    { id: "linkHeavy", unlock: { type: "behavior", stat: "perfectDeals", count: 4 }, label: "Same Heavy", icon: "🧱",
      effect: "linkHeavy", value: 1, hubValue: 3, tier: "rare", price: 9,
      description: "Add +1 pile size to every pile, and +3 to the pile you called Same on" },

    /* ====================== ARCHETYPE BATCH v6.76 =======================
       Engine-implemented since v6.76; gated in v6.80 (a late anchor —
       samesCalled teaches the build). Price is an R4 PROPOSAL, marked TUNE. */
    // RANK FLOOD: board-wide rank rewrite off a correct Same. No knobs — the
    // Joker edge cases (Joker on either side ranks piles by the ranked card;
    // Joker-on-Joker makes Aces) are the mechanic.
    // TUNE: price 9 proposed (R4) — the flat same-power price point.
    { id: "rankFlood", unlock: { type: "behavior", stat: "samesCalled", count: 60 }, label: "Rank Flood", icon: "🌊",
      effect: "rankFlood", tier: "rare", price: 9,
      description: "A correct Same sets the top card of every alive pile to this card's rank. A Joker on either side ranks them by the ranked card; Joker-on-Joker makes Aces" },
  ],

  /* --------------------------------------------------------------------
     PACK-CARD STICKER ODDS — how many stickers one freshly granted card
     carries. [maxRoll, stickerCount] pairs, checked IN ORDER against a
     uniform 0..1 roll (a roll that passes every maxRoll gets 0 stickers);
     maxRoll must strictly ascend. ONE rule for every roll site: store
     card packs, the store's individual-card slot (genNormalCard) and
     Mr. Smith's map grants (+1 nodes / map packs).
  -------------------------------------------------------------------- */
  // v6.73: ONE pack distribution everywhere — 75% bare, 20% one sticker,
  // 4% two, 1% three (checked in order: roll < cap → that many stickers).
  // Sealed map packs roll THIS table in CampaignState.applyPackCardStickers
  // (v6.74 — no hardcoded copy), which also gives each rolled sticker a 5%
  // chance of being a curse.
  packStickerOdds: [[0.01, 3], [0.05, 2], [0.25, 1]],

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
    // WHO takes a ? node — the character rolls FIRST (Old Joker's promises,
    // a due marker or a pending drink, still pre-empt everything), THEN the
    // chosen character's own action rolls by the weights below, restricted
    // to that character's pool.
    characterWeights: { oldJoker: 40, queen: 30, two: 30 },
    weights: {
      coinBonus: 15, cards: 12, stickerPack: 10, freeRemoval: 8,
      stickerStrip: 7, joker: 5, store: 5, cursedSticker: 14,
      coinLoss: 12, ambush: 8,
      // THE CAST'S OWN TRICKS. Banes (Just a Two): stickerTheft strips a
      // random card bare, itemTheft repossesses an equipped Pillar/Base,
      // priceDouble marks the next shop up ×2 until a refresh. Boons (the
      // Beheaded Queen): priceOne flattens the next shop to 1 coin per item
      // until a refresh, freeRefresh comps the next shop's first REFRESH,
      // freeRedeal comps the next deal's first RESHUFFLE.
      stickerTheft: 6, itemTheft: 5, priceDouble: 6,
      priceOne: 6, freeRefresh: 6, freeRedeal: 6,
      // shieldDrain empties a charged Same shield (folds off when empty);
      // shieldCharge fills an empty one (folds off when charged); coinDouble
      // doubles the purse (folds off at 0); giftCard mints a 2–3-sticker
      // card into the tray to swap in.
      shieldDrain: 5, shieldCharge: 5, coinDouble: 4, giftCard: 5,
      // mammaLie: the Two's con — it claims it can take you to Mamma for all
      // your coins or a ★ Joker. It is LYING; it takes and gives nothing.
      // Only rolls to a real offer when a Joker is held (folds to a Toll).
      mammaLie: 4,
      // twoGame: the Two's card game — one red-or-black call against the
      // COLOR of its hidden card (♥♦ red, ♠♣ black; the hidden card is one of
      // the four standard suits, never a ★ Joker). Winning pays NOTHING;
      // losing drains the Same shield. Only rolls when the shield is
      // charged (folds to a Toll), so the stake is always real.
      twoGame: 5,
    },
    // [min,max] coin swing per stage — the stakes grow with the climb.
    // coinLoss at 0 coins flips to coinBonus (apply-time fold, deterministic).
    coinRangeByStage: [[3, 6], [6, 11], [10, 17]],
    cardGrantRange: [1, 3],
    ambush: { cards: 15, piles: 4, bounty: 15 },
  },

  /* --------------------------------------------------------------------
     THE OLD JOKER — a recurring character who sometimes intercepts a
     mystery ("?") node instead of the plain outcome rolling. He always
     OFFERS; declining is always free, and is sometimes the right play.

     His SHARE of the ? nodes lives in mystery.characterWeights (the
     character roll happens FIRST — Old Joker vs Queen vs Two — then the
     action within the character rolls by its weight). His roll still runs
     on its OWN seeded substream, so retuning it never disturbs the
     ordinary mystery outcome stream.
     weights        relative odds per offer. ONLY offers that are currently
                    eligible are rolled (no equipped items → no Buyout), so
                    the effective mix shifts with the run's state.
     Every numeric below is a hand-tunable knob; nothing is hardcoded in
     logic.
  -------------------------------------------------------------------- */
  oldJoker: {
    weights: {
      buyout: 12, swap: 10, purge: 8, ride: 7, cut: 12,
      marker: 8, blindSwap: 9, twoDoors: 12, insurance: 10, refund: 8,
      freeShop: 8, purgeReset: 6, eights: 6, thirsty: 10, duplicate: 9,
      // A ★ Joker for EVERY equipped Pillar — only offered when at least one
      // Pillar is up and the tier's joker cap has room.
      jokerForPillars: 7,
    },
    // BUYOUT: he names TWO of your equipped items and prices EACH with its
    // own independent roll (v6.80): premiumChance of a premium offer
    // (highMinMult..highMaxMult × the item's price), else a lowball
    // (lowMin..lowMaxMult × price). So mixed 50%, both lowball 25%, both
    // premium 25% at the default 0.5.
    buyout: { lowMin: 1, lowMaxMult: 1, highMinMult: 2, highMaxMult: 3, premiumChance: 0.5 },
    // PURGE: remove `removeCount` cards you choose, at the cost of a curse
    // landing on `leechCount` others. WHICH curse each card gets comes from
    // the shared weighted curse roll (curseWeight, path "purge").
    purge: { removeCount: 3, leechCount: 3 },
    // CUT: free when HE picks the card, `chooseCost` coins to pick it yourself.
    cut: { chooseCost: 4 },
    // RIDE: he drives you to the next shop this stage. `cost` coins for the
    // lift — the stops it skips are the real price, this is the fare.
    ride: { cost: 5 },
    // MARKER: a loan. `min`..`max` coins now; when he later collects he takes
    // `repayMult` × what he gave (floored at your purse — never below zero).
    // `collectChance` is the per-mystery odds he is waiting to collect. The
    // player is never told those odds.
    marker: { min: 12, max: 20, repayMult: 1.5, collectChance: 0.2 },
    // BLIND SWAP: one of your COMMON items for something better, unseen.
    blindSwap: { fromTier: "common", toTiers: ["uncommon", "rare"] },
    // TWO DOORS: one door is drawn from `good`, the other from `bad`; which
    // door hides which is seeded per node.
    twoDoors: {
      good: ["coinBonus", "cards", "stickerPack", "freeRemoval"],
      bad: ["coinLoss", "cursedSticker", "ambush"],
    },
    // INSURANCE: only offered with the Same Charge EMPTY.
    insurance: { cost: 2 },
    // REFUND: he points at ONE of your equipped items (rolled — v6.62: no
    // longer a choice of two) and pays `minMult`–`maxMult` × the item's OWN
    // price for it. Sell it to him, or walk.
    // (v6.50: the dead per-tier fields here were removed - they implied a
    // sell-value formula the code never used.)
    refund: { count: 1, minMult: 2, maxMult: 3 },
    // FREE SHOP: he NAMES one equipped item; hand it over and the next store
    // visit is on him. `freeKinds` is what the comp actually covers — the
    // Purge slot is deliberately excluded (a free repeatable card-delete would
    // let one visit strip the whole deck). The comp dies on the first REFRESH:
    // that shelf is his gift, the next one you pay for.
    freeShop: { freeKinds: ["sticker", "pillar", "base", "samepower", "pack", "card"] },
    // PURGE HALVING: he halves the Purge slot's CURRENT price on the spot —
    // but the ladder's step grows by `stepIncrease` for the rest of the climb
    // (2 → 3 → 4 …), so taking this repeatedly costs more each time. Only
    // offered once the ladder has actually climbed. `cost` is his fee.
    purgeReset: { cost: 0, stepIncrease: 1 },
    // EIGHTS: every card in your deck at one of `from` becomes `to`. Ace is
    // 14, so this eats your highest and lowest — and he pays nothing for it.
    // The flatter deck IS the offer: fewer extremes to read, fewer gimmes.
    eights: { from: [14, 2], to: 8 },
    // THIRSTY: he asks for drink money, any amount, your call. Pay him and he
    // returns at the NEXT mystery node with items worth `rewardMult` × what
    // you gave. Stiff him and he returns for an ambush instead — `ambushCards`
    // over `ambushPiles` piles, paying `ambushBounty` if you clear it.
    // `returnChance`: once the drink is bought (or refused) he does NOT
    // promise the very next "?" — every mystery node rolls this chance until
    // the one where he turns up to settle it.
    // `charity`: what he hands a player whose purse is EMPTY when he asks
    // (v6.81) — shared hard luck, no return visit, no ambush. Only a refusal
    // from a purse that HAD coins arms the comeback.
    thirsty: { rewardMult: 2, ambushCards: 18, ambushPiles: 4, ambushBounty: 1, returnChance: 0.25, charity: 3 },
    // DUPLICATE: copy any non-Joker card in your deck, stickers and all, then
    // choose which card the copy REPLACES. The copy carries a curse from the
    // shared weighted roll (path "duplicate" — mild band only).
    duplicate: {},
    // JOKER FOR PILLARS: every equipped Pillar leaves, a ★ Joker joins the
    // deck. No knobs — the trade IS the knob — but the block stays so the
    // fail-loud "every offer has its block" rule holds.
    jokerForPillars: {},
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
    dealBase: 2,    // flat base every cleared deal pays before the stage term
    bossBonus: 1,   // extra flat coins a cleared boss pays on top
    // ENDLESS FREEZE (v6.78): the stage term never grows past this stage —
    // endless deals (stage 4, 5, …) pay phase-3 rates for their difficulty
    // forever. 3 = the campaign's last phase.
    stageCap: 3,
  },

  /* --------------------------------------------------------------------
     PACKS — buying reveals `size` random items; the player keeps `keep`.
     Card-pack picks go to the pending pack tray (pre-run deck swap);
     sticker-pack picks go straight to the sticker inventory.
  -------------------------------------------------------------------- */
  packs: [
    { id: "cardPack", unlock: { type: "milestone", stat: "dealsWonRegular", count: 15 }, label: "Large Card Pack", icon: "🎴", kind: "card", tier: "uncommon",
      size: 5, keep: 2, price: 4,
      description: "Reveals 5 random cards. Keep 2 to swap into your deck" },
    { id: "smallCardPack", label: "Small Card Pack", icon: "🎴", kind: "card", tier: "common",
      size: 3, keep: 1, price: 2,
      description: "Reveals 3 random cards. Keep 1 to swap into your deck" },
    { id: "stickerPack", label: "Small Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 3, keep: 1, price: 3,
      description: "Reveals 3 random stickers. Keep 1" },
    { id: "largeStickerPack", unlock: { type: "behavior", stat: "stickersApplied", count: 50 }, label: "Large Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 5, keep: 2, price: 6,
      description: "Reveals 5 random stickers. Keep 2" }
  ],
};
