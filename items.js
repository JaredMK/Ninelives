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
    reroll: { baseCost: 3, step: 1 },
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
      description: "Swap into your deck, replacing a card you choose",
    },
    // The debug-toggleable permanent 6th store slot: fixed price, never
    // depletes, each purchase runs the choose-a-card-to-remove flow.
    // `priceStep` makes the slot climb: every removal bought in a climb adds
    // this much to the next one's price (0 = flat forever). The ladder resets
    // with each new climb, like the reroll ladder resets each shop visit.
    removal: {
      id: "removal", label: "Purge", icon: "∅", price: 3, priceStep: 1,
      description: "Permanently purge a card from your deck — the price climbs each use",
    },
    // ITEM VALUE by tier. v7.02: selling equipped items for coins was
    // removed — this is no longer a store sell price. Its one remaining use
    // is the Old Joker's thirst-coat, which values the gifts it hands out
    // against its budget by these tiers. (His Refund/Buyout OFFERS price off
    // the item's `price`, not this table.) Kept as the coat's internal basis.
    sell: { common: 1, uncommon: 2, rare: 3 },
  },

  /* --------------------------------------------------------------------
     STICKERS — card-bound modifiers ("Imprints"). A card may hold any
     number of stickers, duplicates included. `rankDelta`, `tributeCount`,
     `coinCost`, `value`, `step`, `per`, `max`, `count` are
     effect knobs.
     PRICING (v6.98): flat by rarity — common 1, uncommon 3, rare 5. (The
     old suit-timing convention retired with the suit-locked stickers.)
  -------------------------------------------------------------------- */
  stickers: [
    /* ═══ STICKER CONDITIONAL REWORK (v6.85) ═══════════════════════════════
       Twenty stickers are RETIRED (`inactive: true`): they stay registered —
       old saves keep resolving and firing them — but leave EVERY acquisition
       pool (grantableBase filters them like cursed). The survivors of the
       seven suit families become suit-AGNOSTIC, CONDITIONAL bets: checked
       when the CARRIER lands — if another alive pile's top matches the
       carrier's suit the effect fires; if none does the sticker converts
       into a curse (weighted pool, new "sticker" pathway, severe band
       excluded; live from the card's NEXT landing). With no OTHER alive
       pile the check is exempt (11.7% of real landings — else the endgame
       is a guaranteed curse mill). v6.95: the Payout/Anchor cover punish is
       removed — both are pure deal-end stickers now. The four rank-conditional
       rewrites went live in v6.86/v6.90 (Same-Safe, Recharge Shield, Tap
       Power; Twin Spark went live in v6.97 — the template now holds for EVERY
       conditional sticker). */
    { id: "rankUp",     label: "+1 Rank",     icon: "➕", kind: "rank",     rankDelta: 1,  tier: "common",   price: 1,
      description: "+1 rank (stops at Ace)"},
    { id: "rankDown",   label: "−1 Rank",     icon: "➖", kind: "rank",     rankDelta: -1, tier: "common",   price: 1,
      description: "-1 rank (stops at 2)" },
    { id: "rankUp2", unlock: { type: "milestone", stat: "dealsWonRegular", count: 4 }, label: "+2 Rank",     icon: "⏫", kind: "rank",     rankDelta: 2,  tier: "uncommon", price: 3,
      description: "+2 rank (stops at Ace)" },
    { id: "rankDown2", unlock: { type: "milestone", stat: "dealsSurvived", count: 12 }, label: "−2 Rank",     icon: "⏬", kind: "rank",     rankDelta: -2, tier: "uncommon", price: 3,
      description: "-2 rank (stops at 2)" },
    { id: "randomFixedValue", unlock: { type: "milestone", stat: "runsPlayed", count: 3 }, label: "Random Rank", icon: "🎰", kind: "behavior", behavior: "randomFixedValue", tier: "common", price: 1,
      description: "Randomize rank" },
    { id: "changeSuitRandom", label: "Random Suit", icon: "🎲", kind: "behavior", behavior: "changeSuitRandom", tier: "common", weight: 25, price: 1,
      description: "Randomize suit" },
    { id: "changeSuitSpade",  label: "Change to ♠", icon: "♠️", kind: "behavior", behavior: "changeSuitTo", suit: "♠", tier: "common", weight: 25, price: 1,
      description: "Change to ♠" },
    { id: "changeSuitHeart",  label: "Change to ♥", icon: "♥️", kind: "behavior", behavior: "changeSuitTo", suit: "♥", tier: "common", weight: 25, price: 1,
      description: "Change to ♥" },
    { id: "changeSuitDiamond", label: "Change to ♦", icon: "♦️", kind: "behavior", behavior: "changeSuitTo", suit: "♦", tier: "common", weight: 25, price: 1,
      description: "Change to ♦" },
    { id: "changeSuitClub",   label: "Change to ♣", icon: "♣️", kind: "behavior", behavior: "changeSuitTo", suit: "♣", tier: "common", weight: 25, price: 1,
      description: "Change to ♣" },
    // SAME-SAFE (v6.86): the first held-back rank conditional goes LIVE —
    // the suit nine's contract on the RANK axis: the tie save is gated on
    // another alive pile's top showing this rank, a missed bet converts,
    // no other alive pile is exempt (and saves nothing).
    { id: "tieSafe",    label: "Same-Safe",   icon: "🛡️", kind: "behavior", behavior: "tieSafe", tier: "common", price: 1,
      description: "If another pile shows this rank → safe\nOtherwise → this becomes a curse" },
    // GUARD (v6.85, was "Spade Guard" — id stays suitImmunity): suit-agnostic
    // and conditional. The save reads the CARRIER's own suit against the
    // OTHER pile tops at its landing.
    { id: "suitImmunity", unlock: { type: "behavior", stat: "spadesPlayed", count: 150 }, label: "Guard", icon: "🪬", kind: "behavior", behavior: "suitImmunity", tier: "uncommon", price: 3,
      description: "If another pile shows this suit → safe\nOtherwise → this becomes a curse" },
    { id: "heartGuard", inactive: true, unlock: { type: "milestone", stat: "dealsSurvived", count: 25 }, label: "Heart Guard", icon: "♥️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♥", suits: ["♥"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♥, or a ♥ lands on this card" },
    { id: "diamondGuard", inactive: true, unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 100 }, label: "Diamond Guard", icon: "♦️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♦", suits: ["♦"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♦, or a ♦ lands on this card" },
    { id: "clubGuard", inactive: true, unlock: { type: "behavior", stat: "cardsBuried", count: 120 }, label: "Club Guard",  icon: "♣️🪬", kind: "behavior", behavior: "suitImmunity", suit: "♣", suits: ["♣"], tier: "uncommon", price: 5,
      description: "Safe if this card lands on a ♣, or a ♣ lands on this card" },
    // value = coins per Extra Coin UNIT (units = stickers on the alive top card
    // × cards in that pile; Economy multiplies units by this value).
    // v6.95: the cover punish is GONE — Payout is a pure deal-end sticker.
    { id: "extraCoin",  unlock: { type: "behavior", stat: "perfectDeals", count: 1 }, label: "Payout",      icon: "💰", kind: "behavior", behavior: "extraCoin", value: 1, tier: "uncommon", price: 3,
      description: "At deal end if top card → earn coins equal to pile size" },
    { id: "gainCoin",   label: "Bonus Coin",  icon: "🍀", kind: "behavior", behavior: "gainCoin", value: 1, tier: "uncommon", price: 3,
      description: "If another pile shows this suit → +1 coin per pile with matching suit\nOtherwise → this becomes a curse" },
    { id: "anchor",     label: "Anchor",      icon: "⚓", kind: "behavior", behavior: "anchor", tier: "common", price: 1,
      description: "At deal end if top card → exclude from smallest-pile size" },
    { id: "deathBounty", inactive: true, label: "Last Coin",  icon: "💀", kind: "behavior", behavior: "deathBounty", value: 3, tier: "common", price: 2,
      description: "+3 coins if it kills a pile", suits: ["♥"] },
    // v6.94: the flat pile-size family is RETIRED (inactive) — Heavy, Streak
    // Size, Massive Diamond, Empty Ranks Heavy, Crazy Eights, Diamond Echo,
    // Pauper's Diamond, Diamond Lifeline, Diamond Boost, Same Heavy. Effects
    // still resolve in old saves; redistribution (Ballast, Donate, Diamond
    // Distribution) and the Anchors stay LIVE — they change board decisions.
    // value = pile size added to each matching pile on a hit (v6.85: a
    // LANDING effect now, latched via sizeBonus — no longer a passive weight).
    { id: "heavy", inactive: true, label: "Heavy",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 1, tier: "uncommon", price: 1,
      description: "If another pile shows this suit → +1 pile size to every pile whose top matches, including this one.\nOtherwise → this sticker becomes a curse" },
     { id: "massive", inactive: true, unlock: { type: "behavior", stat: "stickersApplied", count: 10 }, label: "Massive",       icon: "🧱", kind: "behavior", behavior: "heavy", value: 2, tier: "uncommon", price: 2,
      description: "+2 pile size",suits: ["♦"]  },
    { id: "collector", inactive: true, unlock: { type: "behavior", stat: "stickersApplied", count: 90 }, label: "Collector",   icon: "🧲", kind: "behavior", behavior: "collector", value: 1, tier: "uncommon", price: 1,
      description: "+1 coin per other sticker on this card", suits: ["♥"] },
    // step = coins the payout grows per correct placement (pays 0 on the first).
    { id: "compound", inactive: true, unlock: { type: "milestone", stat: "bestCampaignScore", count: 120 }, label: "Compound",    icon: "📈", kind: "behavior", behavior: "compound", step: 1, tier: "rare", price: 6,
      description: "+X coins. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess", suits: ["♥"] },
    { id: "revealNext", inactive: true, unlock: { type: "behavior", stat: "zenEasyWon", count: 2 }, label: "Scout",       icon: "👁️", kind: "behavior", behavior: "revealNext", tier: "rare", price: 10,
      description: "Peek at the next deck card", suits: ["♠"]  },
    { id: "wildSuit", inactive: true,   label: "Wild Suit",   icon: "♠♥♦♣", kind: "behavior", behavior: "wildSuit", tier: "common", price: 1,
      description: "Counts as every suit" },
    { id: "shuffle", inactive: true, label: "Shuffle",     icon: "🔀", kind: "behavior", behavior: "shuffle", tier: "uncommon", price: 1,
      description: "Optionally shuffle the pile", suits: ["♦"]  },
    // v6.85: conditional — the fire equalises EVERY alive pile (board-wide).
    { id: "donate",     label: "Donate",      icon: "🤝", kind: "behavior", behavior: "donate", count: 1, tier: "uncommon", price: 3,
      description: "If another pile shows this suit → make all pile sizes equal size\nOtherwise → this becomes a curse" },
    // UNGATED on purpose: with Bury 1 retired, Quick Bury is the cardsBuried
    // unlock ladder's only seed source (chicken-and-egg otherwise).
    // v6.85: conditional — the carrier's suit is the bet.
    { id: "quickBury", label: "Quick Bury",  icon: "⚡", kind: "behavior", behavior: "quickBury", tier: "uncommon", price: 3,
      description: "If another pile shows this suit → bury 1 card under this pile\nOtherwise → this becomes a curse" },
    { id: "twinSpark", unlock: { type: "behavior", stat: "zenGamesPlayed", count: 4 }, label: "Twin Spark",  icon: "✨", kind: "behavior", behavior: "twinSpark", tier: "uncommon", price: 3,
      description: "If another pile shows this rank → peek next card\nOtherwise → this becomes a curse" },
    // max = the top of the random 0–max coin roll.
    { id: "looseChange", inactive: true, unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 60 }, label: "Loose Change", icon: "🪙", kind: "behavior", behavior: "looseChange", max: 3, tier: "uncommon", price: 2,
      description: "+0–3 coins (random)", suits: ["♥"] },
    // step = how much X (cards buried) grows per correct placement.
    { id: "snowball", inactive: true, unlock: { type: "behavior", stat: "perfectDeals", count: 6 }, label: "Snowball Bury", icon: "☃️", kind: "behavior", behavior: "snowball", step: 1, tier: "rare", price: 10,
      description: "Bury X cards. X starts at 0, grows by 1 each correct placement, resets to 0 on a wrong guess", suits: ["♣"] },
    // per = deck cards per +1 coin (floor(deck remaining ÷ per)).
    { id: "deepPockets", inactive: true, unlock: { type: "milestone", stat: "bestCoinsInClimb", count: 140 }, label: "Deep Pockets", icon: "👛", kind: "behavior", behavior: "deepPockets", per: 10, tier: "uncommon", price: 3,
      description: "+1 coin per 10 cards left in the deck", suits: ["♥"]},
    { id: "pillarScout", unlock: { type: "behavior", stat: "pillarsPlaced", count: 12 }, label: "Pillar Scout", icon: "🔭", kind: "behavior", behavior: "pillarScout", tier: "uncommon", price: 3,
      description: "If in column with no Pillar → peek next card\nOtherwise → this becomes a curse" },
    { id: "baseScout", unlock: { type: "behavior", stat: "basesPlaced", count: 12 }, label: "Base Scout",  icon: "🔎", kind: "behavior", behavior: "baseScout", tier: "uncommon", price: 3,
      description: "If in column with no Base → peek next card\nOtherwise → this becomes a curse" },
    // ---- the Snob family: BIDIRECTIONAL — fires when a matching-suit card lands on
     // this card, AND when this card lands on a matching-suit pile top ----
    { id: "suitSnob", inactive: true, unlock: { type: "behavior", stat: "spadesPlayed", count: 60 }, label: "Spade Snob",  icon: "🧐", kind: "behavior", behavior: "suitSnob", tier: "uncommon", price: 4,
      description: "When a ♠ lands on this card, or this card lands on a ♠ → peek at the next card", suits: ["♠"] },
    // value = coins paid per Heart Snob on the landing card.
    { id: "heartSnob", inactive: true, unlock: { type: "behavior", stat: "heartsPlayed", count: 75 }, label: "Heart Snob",  icon: "💞", kind: "behavior", behavior: "heartSnob", value: 2, tier: "uncommon", price: 2,
      description: "When a ♥ lands on this card, or this card lands on a ♥ → +2 coins", suits: ["♥"] },
    // RIPPLE (v6.85, was "Diamond Snob" — id stays diamondSnob, ids are
    // stable keys): suit-agnostic, conditional, and the shuffle is OFFERED.
    { id: "diamondSnob", unlock: { type: "behavior", stat: "removalsUsed", count: 18 }, label: "Ripple", icon: "🌊", kind: "behavior", behavior: "diamondSnob", tier: "uncommon", price: 3,
      description: "If another pile shows this suit → optionally shuffle those piles\nOtherwise → this becomes a curse" },
    // digCount = deck cards buried under the pile per Club Snob.
    { id: "clubSnob", inactive: true, unlock: { type: "behavior", stat: "pilesLost", count: 40 }, label: "Club Snob",   icon: "🍀", kind: "behavior", behavior: "clubSnob", digCount: 1, tier: "uncommon", price: 10,
      description: "When a ♣ lands on this card, or this card lands on a ♣ → bury 1 deck card under the pile", suits: ["♣"] },
    // ---- the suit-SYNERGY family: each fires when THIS card lands, scaling
    // by the number of OTHER piles topped by its suit (the landing pile
    // itself never counts). ----
    // value = coins per other ♥-topped pile.
    { id: "heartChoir", inactive: true, unlock: { type: "behavior", stat: "heartsPlayed", count: 200 }, label: "Heart Choir", icon: "💕", kind: "behavior", behavior: "heartChoir", value: 1, tier: "uncommon", price: 3,
      description: "+1 coin per each pile with a ♥ top card", suits: ["♥"] },
    { id: "diamondRipple", inactive: true, unlock: { type: "behavior", stat: "perfectDeals", count: 8 }, label: "Diamond Ripple", icon: "🌊", kind: "behavior", behavior: "diamondRipple", tier: "uncommon", price: 2,
      description: "Shuffle every other pile with a ♦ top card", suits: ["♦"] },
    // RANK ROOTS (renamed from Club Roots, v6.78 — same id, saves bind to
    // it): the trigger is now RANK-match, not ♣-tops. digCount = deck cards
    // buried under each OTHER pile whose top matches this card's rank when
    // it lands (the landing pile itself never counts — the synergy-family
    // rule).
    { id: "clubRoots", inactive: true, unlock: { type: "behavior", stat: "clubsPlayed", count: 120 }, label: "Rank Roots", icon: "🌱", kind: "behavior", behavior: "clubRoots", digCount: 1, tier: "rare", price: 8,
      description: "When this card lands → bury 1 card under each pile whose top card matches this card's rank", suits: ["♣"] },
    { id: "spadeWhispers", inactive: true, unlock: { type: "behavior", stat: "spadesPlayed", count: 200 }, label: "Spade Whispers", icon: "🌬️", kind: "behavior", behavior: "spadeWhispers", tier: "rare", price: 8,
      description: "The next X cards show a hint (higher/lower/same), where X = other piles with a ♠ top card", suits: ["♠"] },
    // step = coins X grows per correct placement (resets to 0 on a wrong one).
    { id: "tell", label: "Tell",        icon: "🔮", kind: "behavior", behavior: "tell", tier: "uncommon", price: 3,
      description: "If another pile shows this suit → this card shows a tell (higher/lower/same)\nOtherwise → this becomes a curse" },
    // ---- Same-charge / Same-power stickers (CONDITIONAL, v6.90) ----------
    // The last two held-back rank conditionals go LIVE on the shared v6.85
    // template: the CARRIER's rank is the bet, read against the OTHER alive
    // tops at its landing — a hit fires, a miss converts (the ~21% hold
    // rate is the INTENDED risk), no other alive pile is exempt.
    { id: "rechargeSameShield", unlock: { type: "behavior", stat: "correctSames", count: 10 }, label: "Recharge Shield", icon: "🛡️", kind: "behavior", behavior: "rechargeSameShield", tier: "uncommon", price: 3,
      description: "If another pile shows this rank → charge Same Shield\nOtherwise → this becomes a curse" },
    { id: "activateSamePower", unlock: { type: "behavior", stat: "correctSames", count: 34 }, label: "Tap Power", icon: "🔗", kind: "behavior", behavior: "activateSamePower", tier: "uncommon", price: 3,
      description: "If another pile shows this rank → fire Same Power\nOtherwise → this becomes a curse" },
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
    //                  "mystery", "doors",
    //                  "sticker" (v6.85: a conditional sticker's failed-bet
    //                  conversion — the severe band is excluded so a missed
    //                  suit read can never destroy a Pillar or Base).
    // price: 0 (never sold).
    { id: "leech",      label: "Leech",       icon: "🪱", kind: "behavior", behavior: "tributeCoin", value: 3, tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. −3 coins" },
    { id: "shrink",     label: "Shrink",      icon: "🪆", kind: "behavior", behavior: "shrink", value: 1, tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. Counts −1 toward pile size" },
    { id: "mute",       label: "Mute",        icon: "🤐", kind: "behavior", behavior: "mute", tier: "common", price: 0, cursed: true, curseWeight: 10,
      description: "Cursed. While top card → Same cannot be called on this pile" },
    { id: "trapdoor",   label: "Trapdoor",    icon: "🕳", kind: "behavior", behavior: "trapdoor", tier: "common", price: 0, cursed: true, curseWeight: 8,
      description: "Cursed. On landing → the pile's bottom card returns to the deck" },
    { id: "spoiler",    label: "Spoiler",     icon: "🍂", kind: "behavior", behavior: "spoiler", tier: "common", price: 0, cursed: true, curseWeight: 6,
      description: "Cursed. Reset bonus coins earned this deal to 0" },
    { id: "drainShield", label: "Shield Drain", icon: "🫗", kind: "behavior", behavior: "drainShield", tier: "common", price: 0, cursed: true, curseWeight: 6,
      description: "Cursed. Drain the Same Shield" },
    // ---- medium band: excluded from DUPLICATE (its curse stays mild) --------
    { id: "flatline",   label: "Flatline",    icon: "📉", kind: "behavior", behavior: "flatline", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While top card → this pile's size is 1" },
    { id: "magnet",     label: "Magnet",      icon: "🧲", kind: "behavior", behavior: "magnet", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While top card → your next guess must be played here" },
    { id: "jammer",     label: "Jammer",      icon: "🔇", kind: "behavior", behavior: "jammer", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. While top card → the column's Pillar does not work" },
    { id: "peeler",     label: "Peeler",      icon: "🥔", kind: "behavior", behavior: "peeler", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. A card landing on this card loses its stickers" },
    { id: "drainBase",  label: "Base Drain",  icon: "🪫", kind: "behavior", behavior: "drainBase", tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. The column's Base is drained" },
    { id: "malfunction", label: "Malfunction", icon: "💥", kind: "behavior", behavior: "malfunction", chance: 0.1, tier: "common", price: 0, cursed: true, curseWeight: 5, curseExclude: ["duplicate"],
      description: "Cursed. 10% chance to kill the pile even on a correct guess" },
    // ---- severe: item destruction. NEVER from Purge or Duplicate -----------
    { id: "saboteur",   label: "Saboteur",    icon: "🧨", kind: "behavior", behavior: "saboteur", chance: 0.1, tier: "common", price: 0, cursed: true, curseWeight: 20, curseExclude: ["purge", "duplicate", "sticker"],
      description: "Cursed. 10% chance to destroy the column's Base or Pillar" },
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
      kind: "scoring", effect: "suitBounty", suit: "♥", value: 1, tier: "common", price: 6,
      description: "When a ♥ lands in this column → +1 coin" },
    { id: "columnTieSafe", unlock: { type: "behavior", stat: "samesCalled", count: 12 }, label: "Column Tie-Safe", icon: "🛡️",
      kind: "guess", effect: "columnTieSafe", tier: "uncommon", price: 6,
      description: "Any tie is safe in this column" },
    // value = coins paid when the column is completely WIPED OUT at deal end
    // (the mirror of Guardian). Pays nothing if a single pile survives.
    { id: "lastLicks", unlock: { type: "behavior", stat: "pilesLost", count: 18 }, label: "Last Licks", icon: "🪦",
      kind: "scoring", effect: "columnNoneAlive", value: 8, tier: "uncommon", price: 6,
      description: "At deal end if no pile in this column survived → +8 coins" },
    { id: "columnGuardian", label: "Guardian", icon: "🏛️",
      kind: "scoring", effect: "columnAllAlive", value: 4, tier: "uncommon", price: 6,
      description: "At deal end if every pile in this column survived → +4 coins" },
    // digCount = deck cards buried per qualifying (sticker-free ♣) landing.
    { id: "clubTribute", inactive: true, unlock: { type: "behavior", stat: "clubsPlayed", count: 150 }, label: "Clean Bury", icon: "🧹",
      kind: "composition", effect: "clubTribute", digCount: 1, tier: "rare", price: 10,
      description: "When a ♣ with no stickers lands in this column → bury 1 card under that pile" },
    { id: "allHeartsCoin", inactive: true, unlock: { type: "milestone", stat: "coinsEarnedLifetime", count: 60 }, label: "All Hearts", icon: "💗",
      kind: "scoring", effect: "allSuitTop", suit: "♥", value: 4, tier: "common", price: 4,
      description: "At deal end → +4 coins if every surviving pile in this column has a ♥ top card" },
    // value = coins per alive ♥-topped pile in this column at end of deal.
    { id: "envy", unlock: { type: "milestone", stat: "runsPlayed", count: 5 }, label: "Envy", icon: "💚",
      kind: "scoring", effect: "heartPiles", value: 2, tier: "uncommon", price: 6,
      description: "At deal end → +2 coins per pile in this column with a ♥" },
    // threshold = the in-column streak step the bonus starts at (+1 size per
    // step from there on; resets on a wrong guess or any other-column guess).
    { id: "streakBank", inactive: true, unlock: { type: "behavior", stat: "perfectDeals", count: 2 }, label: "Streak Size", icon: "🏦",
      kind: "modifier", effect: "streakSize", threshold: 3, tier: "rare", price: 4,
      description: "From the 3rd consecutive correct guess in this column → +1 pile size per guess. Resets on a wrong guess or any guess in another column" },
    // threshold = the streak step burials start at; digCount = cards buried
    // per correct in-column guess from that step onward (flat, no escalation).
    { id: "streakTribute", unlock: { type: "behavior", stat: "cardsBuried", count: 90 }, label: "Streak Bury", icon: "🔥",
      kind: "composition", effect: "streakTribute", threshold: 4, digCount: 1, tier: "uncommon", price: 6,
      description: "From the 4th consecutive correct guess in this column → bury 1 card per guess — resets on a wrong guess or a guess in another column" },
    // STREAK COIN (v7.01): Streak Bury's coin twin — same threshold, same
    // resets, `value` coins per in-streak guess.
    { id: "streakCoin", label: "Streak Coin", icon: "🪙",
      kind: "scoring", effect: "streakCoin", threshold: 4, value: 1, tier: "uncommon", price: 6,
      description: "From the 4th consecutive correct guess in this column → +1 coin per guess\nResets on a wrong guess or a guess in another column" },
    // value = the CAP this column may be widened to. The board's normal 3-way
    // split runs first, then this column gains ONE seat, never past `value` —
    // so a 1-pile column opens with 2 and a column already at the cap is
    // untouched. Ditto mirroring this widens the mirroring column too.
    { id: "fourthSeat", unlock: { type: "milestone", stat: "endlessStagesReached", count: 1 }, label: "Fourth Seat", icon: "🪑",
      kind: "composition", effect: "columnPiles", value: 4, tier: "uncommon", price: 6,
      description: "This column starts each deal with 1 extra pile (max 4)" },
    { id: "secondWind", label: "Second Wind", icon: "🌬️",
      kind: "guess", effect: "secondWind", tier: "uncommon", price: 6, saveChance: 0.25,
      description: "When a pile in this column dies → 25% chance to save it: the top card stays, the buried cards shuffle back into the deck" },
    // GREEDY (v6.93 rework): the fat-deck / empty-loadout archetype piece —
    // it scales WITH deck size while the rest of the game punishes bloat,
    // and only pays while the board carries no other pillar. value = coins
    // per chunk; perCards = the deck-size chunk that pays one chunk.
    { id: "greedy", unlock: { type: "milestone", stat: "dealsSurvived", count: 6 }, label: "Greedy", icon: "🤑",
      kind: "scoring", effect: "greedy", value: 1, perCards: 5, tier: "uncommon", price: 6,
      description: "At deal end if only equipped pillar → +1 coin per 5 cards in your full deck" },
    { id: "highestEven", inactive: true, unlock: { type: "milestone", stat: "bestCampaignScore", count: 220 }, label: "Highest Heart", icon: "💗",
      kind: "scoring", effect: "highestHeart", tier: "rare", price: 8,
      description: "At deal end → earn coins equal to the highest numbered ♥ top card in this column (2–10 face value, Ace pays 1, royals pay 0)" },
    // minStickers = stickers a landing ♣ must carry; digCount = cards buried.
    { id: "denseBury", unlock: { type: "behavior", stat: "stickersApplied", count: 140 }, label: "Dense Bury", icon: "🧊",
      kind: "composition", effect: "denseBury", minStickers: 3, digCount: 1, tier: "uncommon", price: 6,
      description: "When a ♣ with 3+ stickers lands correctly in this column → bury 1 card under that pile" },
    // trigger = the pile size (cards) that arms the one-shot revive offer.
    { id: "revive", unlock: { type: "milestone", stat: "dealsWonLegendary", count: 4 }, label: "Revive", icon: "♻️",
      kind: "guess", effect: "revive", trigger: 10, tier: "uncommon", price: 6,
      description: "When a pile in this column reaches 10 cards → revive one dead pile" },
    // BULK RATE (v6.98): the store's Purge ladder climbs `value` less per
    // purchase while equipped — against the flat ladder's step of 1 that is
    // a full stop (an Old Joker-steepened ladder still creeps by the
    // difference). Pure derived pricing — no saved state of its own.
    { id: "bulkRate", unlock: { type: "behavior", stat: "removalsUsed", count: 16 }, label: "Bulk Rate", icon: "🏷️",
      kind: "meta", effect: "purgeStepDiscount", value: 1, tier: "uncommon", price: 6,
      description: "The store's Purge price does not climb (no effect during deal)" },
    // FREEBIE: one random shelf item per store visit costs 0 — rolled from
    // the same seeded store stream, so a reload shows the same gift.
    { id: "freebie", unlock: { type: "behavior", stat: "pinkyTipsSeen", count: 2 }, label: "Freebie", icon: "🎁",
      kind: "meta", effect: "freebie", tier: "uncommon", price: 6,
      description: "One random item in every store costs 0 (no effect during deal)" },
    // RARE HUNTER: the store's rare tier weight is multiplied by `value`
    // while equipped (20 → 40 against common 100 / uncommon 50).
    { id: "rareHunter", unlock: { type: "behavior", stat: "pillarsPlaced", count: 25 }, label: "Rare Hunter", icon: "🦅",
      kind: "meta", effect: "rareHunter", value: 2, tier: "uncommon", price: 6,
      description: "Rare items appear in the store twice as often (no effect during deal)" },
    // BOUNCER: a campaign-level ward — 30% to turn JUST A TWO away at a ?
    // node; CERTAIN when the deck holds no 2s at all (v6.87 — reads the
    // full deck at the node). He still appears, says "Ah, nothing for you
    // today.", and takes nothing. No in-deal effect; the engine never sees it.
    // v7.01 HYBRID: the ward chance rises to 50% and a CURSED landing in
    // the column loses its curses permanently (the Cleanse contract —
    // .cursePeeled writes the campaign identity). A curse converted DURING
    // the landing is dormant (freshCurses) and survives it.
    { id: "twoWard", unlock: { type: "behavior", stat: "jokersPlayed", count: 4 }, label: "Bouncer", icon: "🚪",
      kind: "meta", effect: "twoWard", chance: 0.5, tier: "uncommon", price: 6,
      description: "50% chance to turn away a Just a Two mystery\n100% if your full deck has no 2s\nWhen a cursed card lands in this column → remove that curse from the card" },
    // QUEEN-FINDER (v6.87): the Bouncer's twin on the QUEEN side of the
    // mystery split. Rolls ride their OWN salted substream (queenFinderSalt)
    // so the main mystery key stream never shifts; the 100% branch (Queens
    // STRICTLY the most common rank — a tie doesn't count) also outranks
    // the Old Joker's claim on the node. Cost/unlock proposed — STOP-FLAGGED
    // in the batch report.
    // v7.01 HYBRID: the finder chance rises to 50%, the 100% branch reads
    // the SHARED most-held rule (mostCommonRank, ties → lowest — the old
    // strictly-most-common rule retired with the wording), and a Queen
    // landing in the column pays `value` — the meta pillar earns its slot
    // in-deal too. The "(no effect during deal)" suffix retired with it.
    { id: "queenFinder", unlock: { type: "behavior", stat: "jokersPlayed", count: 6 }, label: "Queen-Finder", icon: "👑",
      kind: "meta", effect: "queenFinder", chance: 0.5, value: 1, tier: "uncommon", price: 6,
      description: "+50% chance to find a Beheaded Queen at a mystery node\n100% if Queens are your most-held rank\nWhen a Queen lands in this column → +1 coin" },
    // FLYPAPER: sticky column — a small chance each landing picks up a
    // random sticker, permanently.
    { id: "flypaper", unlock: { type: "behavior", stat: "stickersApplied", count: 25 }, label: "Flypaper", icon: "🪤",
      kind: "live", effect: "flypaper", chance: 0.05, tier: "uncommon", price: 6,
      description: "When a card lands correctly in this column → 5% chance it gains a random sticker" },
    // {rank} pillars: the rank locks the FIRST time the pillar shows in a
    // shop this climb — Underdog reads your deck's SCARCEST rank, Crowd
    // Favorite its most common (random tiebreak) — and holds all climb.
    { id: "underdog", unlock: { type: "behavior", stat: "cardsBuried", count: 40 }, label: "Underdog", icon: "🐜",
      kind: "composition", effect: "rankBury", digCount: 1, tier: "uncommon", price: 6,
      description: "When a {rank} lands in this column → bury 1 card under that pile" },
    { id: "crowdFavorite", unlock: { type: "milestone", stat: "dealsSurvived", count: 18 }, label: "Crowd Favorite", icon: "📣",
      kind: "live", effect: "rankCoin", value: 2, tier: "uncommon", price: 6,
      description: "When a {rank} lands correctly in this column → +2 coins" },
    // ---- expansion Pillars ------------------------------------------------
    { id: "insurance", unlock: { type: "behavior", stat: "pilesLost", count: 55 }, label: "Insurance", icon: "🛟",
      kind: "scoring", effect: "insurance", value: 8, tier: "uncommon", price: 6,
      description: "At deal end if only one pile is alive → +8 coins" },
    { id: "ditto", unlock: { type: "milestone", stat: "runsWon", count: 1 }, label: "Ditto", icon: "🪞",
      kind: "meta", effect: "ditto", tier: "uncommon", price: 6,
      description: "Mirror the center column's Pillar" },
    // value = extra pile size per ♦ card (top or buried) in the column.
    { id: "stickerCount", inactive: true, label: "Massive Diamond", icon: "🏷️",
      kind: "modifier", effect: "heavyDiamond", value: 2, tier: "uncommon", price: 4,
      description: "♦ cards in this column count as +2 toward pile size" },
    // value = coins per prime-rank (2/3/5/7) card landing correctly here.
    { id: "prime", inactive: true, unlock: { type: "milestone", stat: "bossesBeaten", count: 20 }, label: "Prime", icon: "🔢",
      kind: "live", effect: "prime", value: 1, tier: "rare", price: 3,
      description: "When a prime-rank card (2/3/5/7) lands correctly in this column → +1 coin" },
    { id: "queensEye", label: "Queen's Eye", icon: "👁️",
      kind: "live", effect: "queensEye", tier: "uncommon", price: 6,
      description: "When a royal ♠ (J/Q/K) lands in this column → peek next card" },
    // v6.99: shuffles EVERY pile in the column, the landing pile included
    // (was "the other piles"); still an offer — tap-away declines.
    { id: "royalCourt", label: "Shuffler", icon: "👑",
      kind: "guess", effect: "shuffler", tier: "uncommon", price: 6,
      description: "When a ♦ lands in this column → optionally shuffle this column's piles" },
    // value = coins per buried card in the largest ♥-topped alive pile.
    { id: "excavator", inactive: true, unlock: { type: "behavior", stat: "cardsBuried", count: 60 }, label: "Excavator", icon: "⛏️",
      kind: "scoring", effect: "excavator", value: 1, tier: "uncommon", price: 3,
      description: "At deal end → +1 coin per buried card in this column's largest pile with a ♥ top card" },
    // chance = probability (0–1) the flip pays `value` (no suit requirement).
    { id: "gambler", inactive: true, unlock: { type: "behavior", stat: "jokersPlayed", count: 12 }, label: "Gambler", icon: "🎲",
      kind: "scoring", effect: "gambler", value: 3, chance: 0.5, tier: "uncommon", price: 5,
      description: "At deal end → 50/50: +3 coins or nothing" },
    { id: "lastRites", unlock: { type: "behavior", stat: "dealsWonLegendary", count: 1 }, label: "Last Rites", icon: "🕯️",
      kind: "live", effect: "lastRites", tier: "uncommon", price: 6,
      description: "When a pile in this column dies → peek next card" },
    // selfDestruct = probability (0–1) the Pillar destroys itself each deal end.
    // chance = probability the ♠ landing actually fires the peek.
    { id: "static", inactive: true, unlock: { type: "behavior", stat: "zenMediumWon", count: 2 }, label: "Static", icon: "🔌",
      kind: "live", effect: "static", chance: 0.5, tier: "rare", price: 3,
      description: "When a ♠ lands in this column → 50% chance to peek at the next card" },
    { id: "wildAces", unlock: { type: "behavior", stat: "jokersPlayed", count: 8 }, label: "Wild Aces", icon: "🃏",
      kind: "guess", effect: "wildAces", tier: "uncommon", price: 6,
      description: "Aces count as high or low in this column" },
    { id: "diamondAnchor", unlock: { type: "behavior", stat: "diamondsPlayed", count: 200 }, label: "Diamond Anchor", icon: "⚓",
      kind: "modifier", effect: "diamondAnchor", tier: "uncommon", price: 6,
      description: "At deal end → exclude each ♦-topped pile in this column from the smallest-pile score" },
    { id: "diamondDistribution", unlock: { type: "behavior", stat: "removalsUsed", count: 10 }, label: "Diamond Distribution", icon: "⚖️",
      kind: "guess", effect: "diamondDistribution", tier: "uncommon", price: 6,
      description: "When a ♦ lands in this column → make this column's piles equal size" },

    /* ====================== ARCHETYPE BATCH v6.76 =======================
       Engine-implemented since v6.76. GATING (v6.80, user-approved): the
       simple/early/mid items ship UNGATED as starting items; the mid-late
       and late ARCHETYPE ANCHORS carry `unlock` gates below. Every price
       is an R4 PROPOSAL, marked TUNE. */

    // ---- Deck-composition Pillars — every condition below evaluates against
    //      the FULL deck (board + buried + remaining), LIVE, at each landing.
    // EMPTY RANKS family (v6.87): three legs on ONE derived condition —
    // ranks with zero copies anywhere in the full deck — and NOTHING else
    // shared: three effect keys, three handlers (bury / coins / pile size).
    // The removalsUsed ladder (30/40/50/60 with Royal Sanctuary) is the
    // deck-shaping teaching gate. New gates/costs STOP-FLAGGED in the
    // batch report.
    { id: "zeroRanksBury", unlock: { type: "behavior", stat: "removalsUsed", count: 40 }, label: "Empty Ranks Bury", icon: "🈳",
      kind: "live", effect: "clubZeroRanksBury", tier: "uncommon", price: 6,
      description: "When a ♣ lands in this column → bury 1 card under that pile per rank with zero copies in your full deck" },
    // v6.98 RETRIGGER: fires on the MOST-HELD rank (live, ties → lowest —
    // the Chorus rule), not on ♥ — the Rank Focus bench's coin leg. The
    // effect key is STABLE (the clubRoots rename precedent); {rank} names
    // the live leader wherever a deck exists.
    { id: "heartZeroRanksCoin", unlock: { type: "behavior", stat: "removalsUsed", count: 50 }, label: "Empty Ranks Coins", icon: "🉐",
      kind: "live", effect: "heartZeroRanksCoin", value: 2, tier: "uncommon", price: 6,
      description: "When your most-held rank ({rank}) lands in this column → +2 coins per rank with zero copies in your full deck" },

    /* ---- RANK FOCUS bench (v6.98) — the most-held-rank trigger family.
       The trigger rank is DERIVED LIVE at every landing (full owned deck,
       ties → the LOWEST rank, the shared mostCopiedRank rule) and the
       {rank} template names the current leader. Gates ride the
       removalsUsed deck-shaping ladder — proposals, STOP-FLAGGED in the
       batch report. */
    // Bury leg: scales by the SAME empty-rank count the coins leg pays on.
    // UNCAPPED — the scaling model is in the v6.98 batch report.
    { id: "mostHeldRankBury", unlock: { type: "behavior", stat: "removalsUsed", count: 45 }, label: "Most-Held Bury", icon: "🀄",
      kind: "composition", effect: "mostHeldRankBury", tier: "uncommon", price: 6,
      description: "When your most-held rank ({rank}) lands in this column → bury 1 card under that pile per rank with zero copies in your full deck" },
    // Tell leg (v7.01: the 3+-missing peek clause retired — text and
    // behavior; rare now).
    { id: "mostHeldRankTell", unlock: { type: "behavior", stat: "removalsUsed", count: 25 }, label: "Most-Held Tell", icon: "🎴",
      kind: "live", effect: "mostHeldRankTell", tier: "rare", price: 6,
      description: "When your most-held rank ({rank}) lands in this column → it shows a tell" },
    // RANK GAP: a landing is safe when the full deck holds ZERO copies of a
    // NEIGHBOURING rank. EDGE RULE (v6.98, documented choice): the rank line
    // does NOT wrap and a non-existent neighbour is NOT "absent" — a 2
    // qualifies only via its 3s, an Ace only via its Kings. (Wrapping has no
    // precedent — Ace is high everywhere but Wild Aces; and counting the
    // missing boundary neighbour as absent would make every 2 and Ace
    // unconditionally safe, an unwritten freebie.)
    { id: "rankGapSafe", unlock: { type: "behavior", stat: "removalsUsed", count: 20 }, label: "Rank Gap", icon: "🕳️",
      kind: "guess", effect: "rankGapSafe", tier: "uncommon", price: 6,
      description: "If a card lands in this column and your full deck holds zero copies of the rank above or below it → it is safe" },
    { id: "diamondZeroRanksSize", inactive: true, unlock: { type: "behavior", stat: "removalsUsed", count: 60 }, label: "Empty Ranks Heavy", icon: "🈵",
      kind: "live", effect: "diamondZeroRanksSize", value: 1, tier: "uncommon", price: 8,
      description: "When a ♦ lands in this column → +1 pile size per rank with zero copies in your full deck" },
    // CRAZY EIGHTS: a composition condition (8s the most common rank in the
    // full deck) changes the column's STARTING pile size. The target size 8
    // is the mechanic itself — no knob.
    // TUNE: price 10 proposed (R4); deliberately huge vs normal starting size — flagged for balance.
    { id: "eightStart", inactive: true, unlock: { type: "behavior", stat: "perfectDeals", count: 12 }, label: "Crazy Eights", icon: "8️⃣",
      kind: "composition", effect: "startPileSizeEight", tier: "rare", price: 10,
      description: "If 8s are the most common rank in your full deck → this column's piles start at pile size 8" },
    // ROYAL SANCTUARY: composition-gated guess safety — the no-2s condition
    // is the whole knob.
    // TUNE: price 6 proposed (R4).
    { id: "royalSanctuary", unlock: { type: "behavior", stat: "removalsUsed", count: 30 }, label: "Royal Sanctuary", icon: "🏰",
      kind: "guess", effect: "royalSafeNoTwos", tier: "uncommon", price: 6,
      description: "If your full deck has no 2s → royals (J/Q/K) are always safe in this column" },
    // VOID TRIBUTE: {suit} pillar — the suit locks the FIRST time the pillar
    // shows in a shop this climb and holds all climb (shopRoll: "suit").
    // buryCount = cards buried per qualifying ♣ landing.
    // TUNE: price 8 proposed (R4).
    { id: "absentSuitClubBury", inactive: true, unlock: { type: "behavior", stat: "clubsPlayed", count: 200 }, label: "Void Tribute", icon: "🌫️",
      kind: "live", effect: "absentSuitClubBury", shopRoll: "suit", buryCount: 2, tier: "rare", price: 8,
      description: "If your full deck contains no {suit} → when a ♣ lands in this column, bury 2 cards under that pile" },
    // MAJORITY RULE: {suit} pillar (shopRoll: "suit", same first-shop lock).
    // The 50% majority threshold is the mechanic itself — no knob.
    // TUNE: price 8 proposed (R4).
    { id: "suitMajoritySafe", unlock: { type: "milestone", stat: "bossesBeaten", count: 6 }, label: "Majority Rule", icon: "🗳️",
      kind: "guess", effect: "suitMajoritySafe", shopRoll: "suit", tier: "uncommon", price: 6,
      description: "If half or more of your full deck is {suit} → {suit} cards are safe when they land in this column" },
    // DIAMOND ECHO: the size bonus is DERIVED — +1 per duplicate of the
    // landing card's rank in the full deck — so there is no count knob.
    // TUNE: price 6 proposed (R4).
    { id: "diamondDupeSize", inactive: true, unlock: { type: "behavior", stat: "diamondsPlayed", count: 150 }, label: "Diamond Echo", icon: "👯",
      kind: "live", effect: "diamondDupeSize", tier: "uncommon", price: 6,
      description: "When a ♦ lands in this column → +1 pile size per duplicate of that card's rank in your full deck" },

    // CURSE WARD (v6.88): the curse archetype's COUNTER-piece — in this
    // column a conditional sticker's missed bet does NOT convert: the
    // sticker stays put and simply doesn't fire. Cover punish (Payout /
    // Anchor) is not a conversion and is not warded; a Jammer blocking the
    // pillar re-opens conversions (the shared resolvePillarDef rule).
    // Rarity/cost/unlock proposed — STOP-FLAGGED in the batch report.
    { id: "stickerCurseWard", unlock: { type: "behavior", stat: "stickersApplied", count: 40 }, label: "Curse Ward", icon: "🧿",
      kind: "live", effect: "stickerCurseWard", tier: "uncommon", price: 6,
      description: "Stickers in this column never convert into curses" },
    // FINAL CUT (v6.88): deck-shaping PAYOFF — when this column's LAST
    // alive pile falls, the killer is permanently purged from the deck
    // (removeDeckCard, so it also feeds the removalsUsed unlock ladder).
    // Jokers/Blanks can't be purged. Proposal STOP-FLAGGED in the report.
    { id: "finalPilePurge", unlock: { type: "behavior", stat: "pilesLost", count: 50 }, label: "Final Cut", icon: "🎬",
      kind: "live", effect: "finalPilePurge", tier: "uncommon", price: 6,
      description: "When the last pile in this column dies → permanently purge the card that killed it" },

    // ---- SAME-TOLERANCE family (family: "sameTolerance") -----------------
    // Four relaxations of what survives a SAME call in this column; `tol`
    // selects the rule. ONE same-tolerance pillar per column MAX, enforced
    // at placement (engine work to come — the data carries the family tag
    // now). Every description states the family rule: a survived Same counts
    // as a FULL correct Same — it charges the Same Shield and fires the
    // equipped Same-Power.
    // TUNE: price 9 proposed (R4).
    { id: "sameTolNear", unlock: { type: "behavior", stat: "correctSames", count: 52 }, label: "Close Call", icon: "🤏",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "near", tier: "uncommon", price: 6,
      description: "Same calls are safe on cards ±1 in value in this column — a survived Same counts as a full correct Same (charges the Same Shield, fires your Same-Power)" },
    // TUNE: price 7 proposed (R4).
    { id: "sameTolRoyal", unlock: { type: "behavior", stat: "samesCalled", count: 40 }, label: "Royal Pair", icon: "🤴",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "royalPair", tier: "uncommon", price: 6,
      description: "A royal landing on a royal survives a Same call in this column" },
    // TUNE: price 7 proposed (R4).
    { id: "sameTolSum10", inactive: true, label: "Perfect Ten", icon: "🔟",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "sum10", tier: "uncommon", price: 7,
      description: "Ranks summing to 10 survive a Same call in this column. A survived Same counts as a full correct Same — charges the Same Shield and fires your Same-Power" },
    // SAME SUIT SAFE (v6.83): back to the SUIT match it always ran — a card
    // landing on its own suit is safe here, Same calls included. It briefly
    // became a rank match in v6.82; the suit version is the keeper, held in
    // check by the RARE tier instead (it was uncommon).
    // TUNE: price 6 proposed (R4).
    { id: "sameTolSuit", label: "Same Suit Safe", icon: "🧥",
      kind: "guess", effect: "sameTolerance", family: "sameTolerance", tol: "sameSuit", tier: "uncommon", price: 6,
      description: "A card landing on its own suit is safe in this column" },

    // ---- SHIELDS ----------------------------------------------------------
    // RANK SHIELD (dynamic, v6.78): at the START of each deal the shield
    // re-reads your FULL deck and protects its most common rank. Tie rule:
    // the INCUMBENT (the rank that's been most common longest) keeps the
    // shield until strictly surpassed; a tie with no incumbent picks
    // randomly (deal-seeded). The current rank shows on the plaque and in
    // the {rank} template below.
    // TUNE: price 5 proposed (R4).
    { id: "rankShield", label: "Rank Shield", icon: "🔰",
      kind: "guess", effect: "rankShield", tier: "uncommon", price: 6,
      description: "The most common rank in your full deck ({rank}) is always safe in this column" },
    // SCARCE SUIT (v6.81, was "Daily Suit"): no roll any more — each deal
    // start reads the FULL deck and shields the suit it holds the FEWEST of
    // — a suit at ZERO is the scarcest and IS chosen (v6.82; ties break by
    // the canonical suit order). The id and
    // the effect key are STABLE ("suitShield"/"suitShieldDaily" — saves and
    // engine hooks bind to them); only the player-facing label moved.
    // TUNE: price 6 proposed (R4).
    { id: "suitShield", label: "Scarce Suit", icon: "📉",
      kind: "guess", effect: "suitShieldDaily", tier: "uncommon", price: 6,
      description: "The suit your full deck holds the fewest of is safe when it lands in this column" },

    // ---- ECONOMY / STORE --------------------------------------------------
    // FLAT PURGE (v6.87 rework): an ON-PURCHASE one-shot — the Purge
    // ladder's CURRENT price halves (odd rounds up), never below `value`,
    // and later steps climb from the cut price (the Old Joker's
    // purgeDiscount mechanism, without his steeper-step clawback). The old
    // always-costs-5 `purgeFlat` reader retired with the key. STOP-FLAGGED
    // in the batch report: a one-shot on a permanent pillar slot.
    { id: "purgeFlatFive", label: "Flat Purge", icon: "✋",
      kind: "meta", effect: "purgeHalve", value: 3, tier: "uncommon", price: 6,
      description: "On purchase → halve the store's Purge price (minimum 3, no effect during deal)" },
    // ON THE HOUSE: covers the FIRST restock per store visit AND the FIRST
    // reshuffle per deal, and pays `value` coins at each cleared deal's end
    // (v7.05 — the coin leg is new; a flat deal-end bonus, no condition).
    { id: "firstFree", label: "On the House", icon: "🆓",
      kind: "meta", effect: "firstFree", value: 2, tier: "uncommon", price: 6,
      description: "First restock of each store and first reshuffle of each deal are free. +2 coins at end of deal" },
    // EIGHT BALL (v6.97): a TELL trigger on an 8 landing — the tell arms on
    // the landing pile, reading the next draw's direction. No knobs. The peek
    // retired with the old `eightPeek` effect key (the item id is STABLE —
    // saves and art bind to it; only the effect key moved).
    // TUNE: price 3 proposed (R4).
    { id: "eightPeek", label: "Eight Ball", icon: "🎱",
      kind: "live", effect: "eightTell", tier: "uncommon", price: 6,
      description: "When an 8 lands in this column → tell on that card" },

    // ---- PAUPER family -----------------------------------------------------
    // PAUPER: all four gate on a LIGHT purse — purseBelow = the exclusive
    // coin ceiling, evaluated LIVE at every landing (drop below it mid-deal
    // and the pillar wakes; climb back above and it sleeps). Common + cheap
    // by design: the broke player's comeback kit.
    // PAUPER'S HEART (v6.98): a landing SHIELD now — a ♥ landing in the
    // column is SAFE while the purse is under the ceiling, and a flat-broke
    // purse (exactly 0) ALSO peeks the next card on that landing. Its own
    // effect key (pauperHeartSafe): the v6.96 tell key retired with the
    // tell, as the peek key did before it.
    { id: "pauperHeart", label: "Pauper's Heart", icon: "❤️‍🩹",
      kind: "live", effect: "pauperHeartSafe", purseBelow: 10, tier: "uncommon", price: 6,
      description: "If purse <10 coins → when a ♥ lands in this column it is safe\nIf 0 coins → peek next card" },
    // value = the pile size a ♦ counts toward (board-wide) while broke,
    // replacing the normal +1.
    // TUNE: price 3 proposed (R4).
    { id: "pauperDiamond", inactive: true, label: "Pauper's Diamond", icon: "💎",
      kind: "live", effect: "pauperDiamondSize", purseBelow: 10, value: 2, tier: "common", price: 3,
      description: "While your purse holds under 10 coins → a ♦ landing anywhere on the board counts +2 toward pile size instead of +1" },
    // No knobs — the tell (higher/lower/same) is the mechanic.
    // v6.93: cost 8 (was the family's flat 2 — the tell is the strongest
    // Pauper effect and priced like the weakest).
    { id: "pauperSpade", label: "Pauper's Spade", icon: "🥄",
      kind: "live", effect: "pauperSpadeTell", purseBelow: 10, tier: "uncommon", price: 6,
      description: "If purse <10 coins → when a ♠ lands in this column it shows a tell\nIf 0 coins → all piles show a tell" },
    // digCount = cards buried per qualifying ♣ landing while under the
    // purse ceiling; digCountBroke REPLACES it at exactly 0 coins (v6.98 —
    // the two-tier Pauper bench: broke is good, flat broke is better).
    { id: "pauperClub", label: "Pauper's Fattening", icon: "🍀",
      kind: "live", effect: "pauperClubBury", purseBelow: 10, digCount: 1, digCountBroke: 3, tier: "uncommon", price: 6,
      description: "If purse <10 coins → when a ♣ lands in this column bury 1\nIf 0 coins → bury 3" },

    // PAUPER'S DIAMOND (v6.98, id pauperDiamondEqualize): a NEW item — the
    // pile-size pauperDiamond retired in the v6.94 cull and stays retired.
    // While the purse is under the ceiling a ♦ landing in the column
    // equalises EVERY alive pile (Donate's board-wide walk); at exactly 0
    // coins the landing ALSO offers an optional purge — the player may tap
    // any alive pile board-wide and its top card leaves the deck for good
    // (decline is free; the card beneath becomes the new top, and a
    // one-card pile dies with its card).
    { id: "pauperDiamondEqualize", label: "Pauper's Diamond", icon: "💎",
      kind: "live", effect: "pauperDiamondEqualize", purseBelow: 10, tier: "uncommon", price: 6,
      description: "If purse <10 coins → when a ♦ lands in this column make all piles the same size\nIf 0 coins → optionally purge the top card of any pile board-wide" },

    // ---- CURSE + THINNING ---------------------------------------------------
    // CURSE HARVEST: turns a cursed landing into value. digCount = cards
    // buried per cursed landing; the peek after is fixed (the mechanic).
    // TUNE: price 7 proposed (R4).
    { id: "curseHarvest", label: "Curse Harvest", icon: "🧺",
      kind: "live", effect: "curseBuryPeek", digCount: 1, tier: "uncommon", price: 6,
      description: "When a cursed card lands in this column → bury 1 card under that pile, then peek next card" },
    // CLUB THIN: per = the deck-remaining step the bury scales on;
    // digCount = cards buried per full step.
    // TUNE: price 6 proposed (R4).
    { id: "clubThin", inactive: true, unlock: { type: "behavior", stat: "cardsBuried", count: 150 }, label: "Club Thin", icon: "✂️",
      kind: "live", effect: "clubThin", per: 25, digCount: 1, tier: "uncommon", price: 6,
      description: "When a ♣ lands in this column → bury 1 card per 25 cards remaining in the deck" },
    // RANK PURGE: an ON-PURCHASE purge — {rank} rolls the first time the
    // pillar shows in a shop this climb (shopRoll: "rank"), is shown before
    // purchase, and every copy leaves the deck at buy time. Fires once, at
    // the shop; nothing in-deal.
    // Price 10 is USER-SPECIFIED (not an R4 proposal).
    { id: "purgeRank", label: "Rank Purge", icon: "🗑️",
      kind: "meta", effect: "purgeRank", shopRoll: "rank", tier: "rare", price: 6,
      description: "On purchase → purge every {rank} from your deck (no effect during deal)" },

    // SIZE-ONE DIAMONDS (archetype batch v6.76 — ungated, data only):
    // value = the pile size a ♦ counts toward (board-wide) while the column
    // holds a size-1 pile, replacing the normal +1.
    // TUNE: price 5 proposed (R4).
    { id: "sizeOneDiamonds", inactive: true, label: "Diamond Lifeline", icon: "🔷",
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
      kind: "active", effect: "kamikaze", peekCount: 2, tier: "uncommon", price: 6,
      description: "Kill a random ♠-topped pile in this column → peek the next 2 cards" },
    // v7.01: the all-♠ gate retired — X scales with the ♠ tops instead.
    { id: "spadePeek", unlock: { type: "behavior", stat: "zenHardWon", count: 1 }, label: "Spade Peeker", icon: "🔦",
      kind: "active", effect: "spadePeek", tier: "uncommon", price: 6,
      description: "Peek the next X cards, where X is the number of piles in this column with a ♠ top card" },
    { id: "shuffleColumn", label: "Upheaval", icon: "🌀",
      kind: "active", effect: "shuffleColumn", tier: "uncommon", price: 6,
      description: "Shuffle every pile in this column" },
    { id: "revive", label: "Phoenix", icon: "🔥",
      kind: "active", effect: "reviveBase", tier: "uncommon", price: 6,
      description: "Revive a random dead pile in this column — buried cards return to the deck" },
    { id: "randomSticker", unlock: { type: "behavior", stat: "stickersApplied", count: 30 }, label: "Wild Sticker", icon: "🎲",
      kind: "active", effect: "randomSticker", tier: "uncommon", price: 6,
      description: "Apply a random sticker to a random top card in this column" },
    // BALLAST (v6.88): BOARD-WIDE now — the column walk retired with the
    // text. Same conserve-and-hand-down algorithm, every alive pile.
    { id: "evenOut", label: "Ballast", icon: "🪨",
      kind: "active", effect: "evenOut", tier: "uncommon", price: 6,
      description: "Make every pile on the board equal size" },
    { id: "setValue", unlock: { type: "milestone", stat: "runsWon", count: 2 }, label: "Rank Setter", icon: "🗿",
      kind: "active", effect: "setValue", tier: "uncommon", price: 6,
      description: "Permanently set this column's top cards to the bottom pile's rank" },
    { id: "setSuit", unlock: { type: "milestone", stat: "runsWon", count: 3 }, label: "Suit Setter", icon: "🎨",
      kind: "active", effect: "setSuit", tier: "uncommon", price: 6,
      description: "Permanently set this column's top cards to the bottom pile's suit" },
    // buryPerSticker = deck cards buried per sticker peeled off the pile card.
    { id: "stickerHarvest", unlock: { type: "behavior", stat: "stickersApplied", count: 115 }, label: "Sticker Harvest", icon: "🌾",
      kind: "active", effect: "stickerHarvest", target: "pile", buryPerSticker: 2, tier: "uncommon", price: 6,
      description: "Choose a pile → bury 2 cards per sticker on its top card, then peel all those stickers" },
    { id: "refreshBases", unlock: { type: "behavior", stat: "basesPlaced", count: 25 }, label: "Reactor", icon: "⚛️",
      kind: "active", effect: "refreshBases", tier: "uncommon", price: 6,
      description: "Recharge your other two Bases" },
    // ---- expansion Bases --------------------------------------------------
    // digCount = cards buried under each matching-suit-topped pile.
    { id: "clubDig", unlock: { type: "behavior", stat: "clubsPlayed", count: 250 }, label: "Club Dig", icon: "♣️",
      kind: "active", effect: "suitDig", suit: "♣", digCount: 1, tier: "uncommon", price: 6,
      description: "Bury 1 card under each ♣-topped pile in this column" },
    // peekCount = upcoming cards peeked after the demolition. Destroys THIS
    // column's pillar; with no pillar here the base stays yellow.
    { id: "demolish", unlock: { type: "behavior", stat: "pillarsPlaced", count: 18 }, label: "Demolish", icon: "🔨",
      kind: "active", effect: "demolish", peekCount: 3, tier: "uncommon", price: 6,
      description: "Permanently destroy this column's Pillar → peek the next 3 cards" },
    // coinPerPile = coins gained per ♥-topped pile destroyed.
    { id: "heartDemolish", unlock: { type: "behavior", stat: "heartsPlayed", count: 90 }, label: "Heart Demolish", icon: "💔",
      kind: "active", effect: "heartDemolish", coinPerPile: 4, tier: "uncommon", price: 6,
      description: "Destroy every ♥-topped pile in this column → +4 coins per pile" },
    // coinPerCard = coins gained per ♥ card counted in the column.
    { id: "tax", label: "Heart Tax", icon: "🧾",
      kind: "active", effect: "tax", suit: "♥", coinPerCard: 1, tier: "uncommon", price: 6,
      description: "+1 coin per ♥ card in this column" },
    // ---- Same-charge / Same-power bases (activated, once per deal) ----
    { id: "rechargeSame", unlock: { type: "milestone", stat: "correctSames", count: 28 }, label: "Recharge Cell", icon: "🔋",
      kind: "active", effect: "rechargeSameShield", tier: "uncommon", price: 6,
      description: "Charge the Same Shield" },
    { id: "activateSame", unlock: { type: "behavior", stat: "correctSames", count: 44 }, label: "Power Surge", icon: "⚡",
      kind: "active", effect: "activateSamePower", tier: "uncommon", price: 6,
      description: "Fire your Same-Power" },
    // LAST RESORT: the panic button — bury the WHOLE remaining deck under
    // one pile here and the deal ends as a win, scored normally. Never in a
    // boss deal. It blows itself up AND any base beside it on use.
    { id: "lastResort", unlock: { type: "behavior", stat: "pilesLost", count: 75 }, label: "Last Resort", icon: "🧨",
      kind: "active", effect: "lastResort", tier: "uncommon", price: 6,
      description: "If not a boss deal → bury the whole deck under a pile in this column and win instantly (destroys itself and any adjacent Base)" },
    // EMPTY PURSE (v7.01 rework): the spend BURIES now — 1 card per
    // `perCoins` spent, spread round-robin across this column's alive piles
    // (deck-limited), then one peek regardless of the spend.
    { id: "emptyPurse", unlock: { type: "milestone", stat: "coinsEarnedLifetime", count: 150 }, label: "Empty Purse", icon: "👛",
      kind: "active", effect: "emptyPurse", perCoins: 5, tier: "uncommon", price: 6,
      description: "Spend all your coins → bury 1 card per 5 coins spent, then peek the next card" },
    // SAME TELL: answers exactly one question — is the next card the same
    // rank as a top card ANYWHERE on the board? A match gets the = mark;
    // no match, no word. (v6.62: board-wide, was this-column-only.)
    { id: "sameTell", label: "Same Tell", icon: "🪞",
      kind: "active", effect: "sameTell", tier: "uncommon", price: 6,
      description: "If the next card matches a top card's rank anywhere on the board → that card shows the = mark" },
    // LONE EYE: a plain peek at the next card. (v7.06 — the old
    // "only while no Same-Power is equipped" condition was removed.)
    { id: "lonePeek", unlock: { type: "behavior", stat: "samesCalled", count: 8 }, label: "Lone Eye", icon: "👁",
      kind: "active", effect: "lonePeek", tier: "uncommon", price: 6,
      description: "Peek the next card" },
    // CLUB ORACLE: reads the next card against EVERY ♣ top in its column.
    { id: "clubOracle", unlock: { type: "behavior", stat: "clubsPlayed", count: 90 }, label: "Club Oracle", icon: "🔮",
      kind: "active", effect: "clubTell", tier: "uncommon", price: 6,
      description: "Tell each ♣-topped pile in this column for the next draw (higher/lower/same)" },
    // AMBUSH ONLY. Its light is green during an ambush and red every other
    // deal — it is a panic button you carry for the deals you did not choose.
    { id: "ambushOut", unlock: { type: "behavior", stat: "ambushesWon", count: 3 }, label: "Escape Hatch", icon: "🚪",
      kind: "active", effect: "ambushWin", tier: "uncommon", price: 6,
      description: "If in a Just a Two ambush → clear the deal instantly" },

    /* ====================== ARCHETYPE BATCH v6.76 =======================
       Engine-implemented since v6.76. GATING (v6.80): early/mid bases ship
       UNGATED except Purge Coupon; the anchors (Transmute, Chorus) gate.
       Every price is an R4 PROPOSAL, marked TUNE. */

    // PURGE COUPON (v6.93 rework): the cut is no longer flat — on fire the
    // store's Purge price drops by perDiamond for each ♦-TOPPED pile in this
    // column (a live board read, so it can't fire with none showing). The
    // cut only exists in-deal, so the live ladder preview (current → new
    // price) is COMPUTED at fire time by the deal UI — the data text stays
    // token-free and can never leak a raw {current}/{new} anywhere (the
    // Collection / post-fire popup leaks this replaces). min = the floor
    // the price never drops below. A store-side lever carried on a base.
    // TUNE: price 5 proposed (R4).
    { id: "purgeDiscount", unlock: { type: "behavior", stat: "removalsUsed", count: 3 }, label: "Purge Coupon", icon: "🎟️",
      kind: "active", effect: "purgeDiscount", perDiamond: 1, min: 3, tier: "uncommon", price: 6,
      description: "−1 to the store's Purge price per ♦-topped pile in this column (minimum 3)" },
    // BONUS RESET (v6.88): trade the deal's banked bonus coins for sight.
    // Only fireable while MORE than 1 bonus coin is banked and the deck
    // still holds a card to show. Rarity/cost/unlock proposed — STOP-FLAGGED
    // in the batch report.
    { id: "bonusResetPeek", unlock: { type: "milestone", stat: "coinsEarnedLifetime", count: 80 }, label: "Bonus Reset", icon: "🔄",
      kind: "active", effect: "bonusResetPeek", tier: "uncommon", price: 6,
      description: "Reset bonus coins earned this deal to 0 → peek next card" },
    // TRANSMUTE: an ON-PURCHASE base — it fires at BUY time and never in a
    // deal. Its target {rank} is DERIVED LIVE — the rank your full deck
    // holds the most copies of at buy time (ties → lowest; recomputed for
    // every display, so the shelf always names the current leader). Only
    // the {suit} rolls at the store (shopRoll, first shelf appearance this
    // climb, shown before purchase).
    // TUNE: price 8 proposed (R4).
    { id: "transmute", inactive: true, unlock: { type: "milestone", stat: "bossesBeaten", count: 8 }, label: "Transmute", icon: "⚗️",
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
    // the mechanic. Stays AMBER until at least 1 bonus coin is banked
    // (v6.93: it can't double a non-positive bonus — a 0×2 fire was a
    // wasted charge).
    // TUNE: price 8 proposed (R4).
    { id: "devilsDeal", label: "Devil's Deal", icon: "😈",
      kind: "active", effect: "devilsDeal", tier: "uncommon", price: 6,
      description: "Double bonus coins earned this deal → add a curse to a top card in this column" },
    // CLEANSE: strips every curse off this column's top cards. No knobs.
    // TUNE: price 5 proposed (R4).
    { id: "cleanseColumn", label: "Cleanse", icon: "🧼",
      kind: "active", effect: "cleanseColumn", tier: "uncommon", price: 6,
      description: "Remove all curses from this column's top cards" },
    // CHORUS: the target rank is DERIVED — the rank your full deck holds the
    // most copies of — so there is no rank knob.
    // TUNE: price 8 proposed (R4).
    { id: "chorus", unlock: { type: "milestone", stat: "bestCampaignScore", count: 160 }, label: "Chorus", icon: "🎼",
      kind: "active", effect: "chorus", tier: "uncommon", price: 6,
      // v6.89: {rank} names the LIVE most-common rank wherever the player
      // can see it before firing (shelf, confirm prompt, hold-help) — the
      // generic fallback still reads "your deck's most common rank" where
      // no deck exists yet (unlock popup, Collection).
      description: "Set every top card in this column to {rank}" },
    // MISSING RANK DIG (v7.04 NEIGHBOR rework): per pile in THIS column,
    // count how many of the pile top's two neighbour ranks (one above, one
    // below) hold zero copies in the full deck, and bury that many under it
    // — 0/1/2, capped by construction. Ace and 2 sit at the rank edges and
    // have ONE real neighbour (no wrap — the Rank Gap precedent): a 2 checks
    // only its 3, an Ace only its King, so an edge card buries at most 1.
    { id: "missingRankDig", unlock: { type: "behavior", stat: "removalsUsed", count: 35 }, label: "Missing Rank Dig", icon: "⛏️",
      kind: "active", effect: "missingRankDig", tier: "uncommon", price: 6,
      description: "For each pile in this column → bury 1 card per neighbor rank of its top card missing from your full deck" },
    // DIAMOND BOOST (v6.78: column-wide, no target pick) — value = the pile
    // size added to EVERY ♦-topped pile in the column.
    // TUNE: price 3 proposed (R4).
    { id: "diamondBoost", inactive: true, label: "Diamond Boost", icon: "💠",
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
      effect: "linkBury", value: 1, tier: "uncommon", price: 10,
      // {suit} is the climb-fixed rolled suit (native substitutes it live).
      description: "Bury 1 card under every {suit}-topped pile" },
    { id: "linkRevive", unlock: { type: "behavior", stat: "correctSames", count: 24 }, label: "Rekindle", icon: "🌱",
      effect: "linkRevive", tier: "uncommon", price: 10,
      description: "Revive a dead pile" },
    // value = coins per alive pile on the board (board-wide, not just linked).
    { id: "linkCoins", label: "Dividend", icon: "💰",
      effect: "linkCoins", value: 1, tier: "uncommon", price: 10,
      description: "+1 coin per alive pile" },
    { id: "linkShuffle", label: "Link Shuffler", icon: "🔀",
      effect: "linkShuffle", tier: "uncommon", price: 10,
      description: "Shuffle every alive pile" },
    // CLEANSE ALL (v6.88): the Cleanse Base's board-wide, Same-gated
    // sibling — every correct Same strips every curse from every alive
    // top, durably (.cursePeeled). Distinctness vs the Base reported.
    { id: "sameCleanseAll", unlock: { type: "behavior", stat: "correctSames", count: 40 }, label: "Cleanse All", icon: "🫧",
      effect: "sameCleanseAll", tier: "uncommon", price: 10,
      description: "Clear all curses from every top card on the board" },
    { id: "samePeek", label: "Same Peeker", icon: "👁️",
      effect: "samePeek", tier: "uncommon", price: 10,
      description: "Peek next card" },
    // SECOND SIGHT (v6.78): ONE draw of total vision — every alive pile
    // shows its tell (higher/lower/same) for the next draw only, then the
    // draw consumes them all (the Club Oracle window mechanic, board-wide).
    { id: "linkTell", unlock: { type: "behavior", stat: "correctSames", count: 16 }, label: "Second Sight", icon: "🔮",
      effect: "linkTell", tier: "uncommon", price: 10,
      description: "Every alive pile gets a tell for the next draw (higher/lower/same)" },
    // Sprays the CALLED pile's whole column. Each sticker is rolled from the
    // grantable pool and is PERMANENT — it stays on the card after the deal.
    { id: "linkSticker", unlock: { type: "behavior", stat: "stickersApplied", count: 70 }, label: "Sticker Spray", icon: "🎨",
      effect: "linkSticker", tier: "uncommon", price: 10,
      description: "Apply a random sticker to every top card in this column" },
    // chance = probability (0–1) that a card is purged from the REMAINING deck
    // — it never touches the board, only what is still to come. v6.89: 50%.
    { id: "linkPurge", unlock: { type: "behavior", stat: "removalsUsed", count: 14 }, label: "Long Odds", icon: "🎯",
      effect: "linkPurge", chance: 0.5, tier: "uncommon", price: 10,
      description: "50% chance to purge a card from the deck" },
    { id: "linkHeavy", inactive: true, unlock: { type: "behavior", stat: "perfectDeals", count: 4 }, label: "Same Heavy", icon: "🧱",
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
      effect: "rankFlood", tier: "uncommon", price: 10,
      description: "Set the top card of every alive pile to this card's rank — a Joker on either side ranks them by the ranked card; Joker-on-Joker makes Aces" },
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
     ECONOMY — the flat deal payout (ECON2, v6.86). Coins paid on a cleared
     deal read straight off this ladder:
       dealPayouts[rating - 1]   (4 / 5 / 6 coins)
     rating = the deal's 1..3 stage-relative difficulty
              (RunMap.difficultyScore of the node's targetD). A BOSS deal
              pays the flat bossPayout (7) instead, whatever its rating.
     Ambush deals still pay NO flat base (their bounty is the reward).
     ENDLESS: ratings are computed against each endless phase's own lifted
     band, so endless deals keep paying these same flat rates forever — the
     old v6.78 stageCap freeze is subsumed (there is no stage term left to
     freeze; phase-3 rates ARE the rates).
     Item-driven bonuses (Payout stickers, pillar payouts, the in-run event
     tally) pay ON TOP, unchanged — the flat base is the guaranteed income;
     items are how you get rich.
  -------------------------------------------------------------------- */
  economy: {
    dealPayouts: [4, 5, 6],  // coins by difficulty rating 1 / 2 / 3
    bossPayout: 7,           // any cleared boss deal, flat
  },

  /* --------------------------------------------------------------------
     PACKS — buying reveals `size` random items; the player keeps `keep`.
     Card-pack picks go to the pending pack tray (pre-run deck swap);
     sticker-pack picks go straight to the sticker inventory.
  -------------------------------------------------------------------- */
  packs: [
    { id: "cardPack", unlock: { type: "milestone", stat: "dealsWonRegular", count: 15 }, label: "Large Card Pack", icon: "🎴", kind: "card", tier: "uncommon",
      size: 5, keep: 2, price: 4,
      description: "Reveal 5 random cards — keep 2 to swap into your deck" },
    { id: "smallCardPack", label: "Small Card Pack", icon: "🎴", kind: "card", tier: "common",
      size: 3, keep: 1, price: 2,
      description: "Reveal 3 random cards — keep 1 to swap into your deck" },
    { id: "stickerPack", label: "Small Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 3, keep: 1, price: 3,
      description: "Reveal 3 random stickers — keep 1" },
    { id: "largeStickerPack", unlock: { type: "behavior", stat: "stickersApplied", count: 50 }, label: "Large Sticker Pack", icon: "📦", kind: "sticker", tier: "common",
      size: 5, keep: 2, price: 6,
      description: "Reveal 5 random stickers — keep 2" }
  ],
};
