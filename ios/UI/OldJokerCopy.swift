import Foundation
import GameCore
import UIKit

/// THE OLD JOKER's voice. Cryptic, worn, a little menacing — he has been in the
/// deck a long time and he knows what you did. Kept here, apart from the logic,
/// so the writing can be edited without touching a rule.
///
/// House style: he never explains the mechanics (the offer line does that), he
/// never says "you win/lose", and he is never cheerful.
enum OldJokerCopy {

    static let name = "The Old Joker"

    /// What he says when he turns up, per offer.
    static func line(for offer: OldJoker.Offer) -> String {
        switch offer {
        case .buyout:
            return "Everything you carry has a number on it. Most folks never learn theirs."
        case .swap:
            return "Trade you. Mine's older. Older is not the same as worse."
        case .purge:
            return "Three go in the fire. Something has to keep it lit."
        case .ride:
            return "I'm headed that way. What's between here and there won't miss you."
        case .cut:
            return "One card leaves tonight. Only question is who picks it."
        case .marker:
            return "Take it. Spend it. I'm patient, right up until I'm not."
        case .blindSwap:
            return "Don't look. Looking's how people talk themselves out of good things."
        case .twoDoors:
            return "Two doors. I shuffled them myself, so don't ask me which."
        case .insurance:
            return "That shield of yours is empty. Empty things break first."
        case .refund:
            return "Sell it back. No shame in it."
        case .collect:
            return "There you are. I did say I'd see you again."
        case .freeShop:
            return "One of yours, and the next shop forgets how to charge you."
        case .purgeReset:
            return "That slot's been bleeding you. I can have a word with it."
        case .eights:
            return "Aces and deuces. All that distance, and for what? Come to the middle."
        case .thirsty:
            return "I'm dry. Whatever you can spare. I'm not proud about the amount."
        case .thirstReturn(let paid, _):
            return paid > 0
                ? "You bought me a drink. I don't forget either kind of thing."
                : "You had coins. I watched you keep them."
        case .duplicate:
            return "Anything worth having is worth having twice."
        case .jokerForPillars:
            return "All them flags you're flying. Give me the lot and I'll deal you a star."
        }
    }

    /// The event's NAME — every popup family leads with a title now (the
    /// mystery reveals always carried theirs; his offers were the holdout).
    /// As-authored case, like the mystery titles; the closing modals title
    /// themselves with the Result's headline instead.
    static func title(for offer: OldJoker.Offer) -> String {
        switch offer {
        case .buyout: return "The Buyout"
        case .swap: return "The Trade"
        case .purge: return "The Purge"
        case .ride: return "The Ride"
        case .cut: return "The Cut"
        case .marker: return "The Marker"
        case .blindSwap: return "The Blind Swap"
        case .twoDoors: return "Two Doors"
        case .insurance: return "Insurance"
        case .refund: return "The Buyback"
        case .collect: return "The Collection"
        case .freeShop: return "On the House"
        case .purgeReset: return "The Reset"
        case .eights: return "Eights"
        case .thirsty: return "The Drink"
        case .thirstReturn(let paid, _):
            return paid > 0 ? "The Drink, Repaid" : "About That Drink"
        case .duplicate: return "The Duplicate"
        case .jokerForPillars: return "A Star for Your Flags"
        }
    }

    /// The plain-language terms — this is where the mechanics live, so his
    /// dialogue never has to carry a number it might get wrong.
    static func offerText(for offer: OldJoker.Offer, in c: CampaignState) -> String {
        switch offer {
        case .buyout(let cheap, let cheapCoins, let rich, let richCoins):
            return cheap == rich
                ? "He'll buy \(c.label(rich)) for \(richCoins). That's the number."
                : "He'll buy \(c.label(cheap)) for \(cheapCoins), or \(c.label(rich)) for \(richCoins)."
        case .swap(let taken, let given):
            return "He offers to take \(c.label(taken)) and leave \(c.label(kind: taken.kind, id: given)) in its place."
        case .purge(let removeCount, let curses):
            // He never says WHICH curses — only how many. The reveal after
            // the picker names them.
            return "Choose \(removeCount) cards to purge, but \(curses.count) other cards are cursed"
        case .ride(_, _, let cost):
            return "\(cost) coins for the lift. Ride to the next shop."
        case .cut(let chooseCost):
            return "One card purged. Free if he picks it, \(chooseCost) coins to pick it yourself."
        case .marker(let coins, let repay):
            // The REPAY figure is deliberately unquoted: not knowing what the
            // marker will cost is the whole texture of taking one. `repay` is
            // still carried on the offer — the engine needs it — it is simply
            // never shown until he turns up to collect.
            _ = repay
            return "\(coins) coins now. He may come looking for it later, with interest."
        case .blindSwap(let from, _):
            return "One of your common items for something rarer. Neither is shown until it's done. He wants \(c.label(from))."
        case .twoDoors:
            // No detail line (v6.52): his own opening line says everything the
            // player is allowed to know about the doors.
            return ""
        case .insurance(let cost):
            return "Pay \(cost) coins to charge your Same Shield"
        case .refund:
            // ONE item now (v6.62); its own price is on its button.
            return "He's pointing at your things"
        case .collect(let owed):
            return "The marker is due: \(owed) coins."
        case .freeShop(let taken, _):
            return "Give him \(c.label(taken)). All items in the next shop are free."
        case .purgeReset(let from, let to, _):
            // The step figures are LIVE: base ladder step + resets already
            // taken, then the same plus this bargain's stepIncrease.
            let stepNow = Int(GameData.shared.items.store.removal.priceStep) + c.purgeStepBonus
            let stepAfter = stepNow + GameData.shared.items.oldJoker.int("purgeReset", "stepIncrease", 1)
            return "The cost to purge a card in the shop is cut in half, \(from) down to \(to). But purge cost increases by \(stepAfter)+ each time after instead of \(stepNow)."
        case .eights(let from, let to, let affected):
            let names = from.sorted(by: >).map { rankWord($0) }.joined(separator: " and ")
            return "Every \(names) in your deck becomes a \(to). \(affected) card\(affected == 1 ? "" : "s") in all."
        case .thirsty(let purse):
            return purse > 0
                ? "Give him what you like."
                : "You have nothing to give. He'll remember being asked all the same."
        case .thirstReturn(let paid, _):
            // No price tag on a gift — let the player just enjoy the haul.
            return paid > 0
                ? "He pays his debts in things, not coins."
                : "He wants it out of your hide: a short, ugly deal."
        case .duplicate:
            // WHICH curse stays hidden until the copy is placed (v6.52).
            return "Copy any card, stickers and all, to swap into your deck. The copy will contain a curse though."
        case .jokerForPillars:
            return "Lose your pillars and gain a Joker"
        }
    }

    /// "Ace" reads better than "14" in his mouth.
    private static func rankWord(_ v: Int) -> String {
        switch v {
        case 14: return "Ace"
        case 13: return "King"
        case 12: return "Queen"
        case 11: return "Jack"
        default: return "\(v)"
        }
    }

    /// Every ITEM the offer names, with its registry description.
    ///
    /// He trades in items by NAME ("he takes Wild Sticker and leaves Upheaval"),
    /// and a name is not a decision: outside the shop there is no tile to hold
    /// for help, so the player was being asked to trade two things they could
    /// not look up. The modal prints these under the terms. Copy comes from the
    /// registry, so it can never drift from what the item actually does.
    ///
    /// Blind offers deliberately list only what he SHOWS — naming the hidden
    /// side would give away the very thing the offer is selling.
    static func itemKey(for offer: OldJoker.Offer, in c: CampaignState) -> [(String, String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        func add(kind: OldJoker.Holding.Kind, id: String) {
            let h = OldJoker.Holding(kind: kind, id: id)
            guard let def = c.holdingDef(h), seen.insert("\(kind.rawValue).\(id)").inserted else { return }
            let text = def.description.isEmpty ? "No description." : c.itemDescription(def)
            out.append((def.label, text))
        }
        func add(_ h: OldJoker.Holding) { add(kind: h.kind, id: h.id) }
        switch offer {
        case .buyout(let cheap, _, let rich, _):
            add(cheap); add(rich)
        case .swap(let taken, let given):
            add(taken); add(kind: taken.kind, id: given)
        case .purge:
            // NOTHING (v6.52): naming the rolled curses here revealed the
            // whole bargain up front — they show only when they land on cards.
            break
        case .blindSwap(let from, _):
            add(from)   // the item he WANTS; what he'd give stays hidden
        case .refund(let options, _):
            for h in options { add(h) }
        case .freeShop(let taken, _):
            add(taken)
        case .duplicate:
            break   // the mark stays hidden until the copy is placed (v6.52)
        case .ride, .cut, .marker, .twoDoors, .insurance, .collect,
             .purgeReset, .eights, .thirsty, .thirstReturn:
            break       // these trade in cards, coins and routes, not named items
        case .jokerForPillars:
            break       // drawn as a compare row, never as a text key
        }
        return out
    }

    /// THE TRADE, DRAWN — the standard for every item decision he offers:
    /// the store's EQUIPPED→NEW comparison, one row per thing that would
    /// leave. What you GIVE on the left, what you GET on the right, and
    /// the buttons below are the confirm/walk-away.
    ///
    /// Offers with rows here get NO itemKey — the rows carry the same
    /// registry copy beside the art, so printing both said everything twice.
    static func compareRows(for offer: OldJoker.Offer, in c: CampaignState) -> [OldJokerView.CompareRow] {
        func itemSide(_ h: OldJoker.Holding, tag: String) -> OldJokerView.CompareSide {
            let def = c.holdingDef(h)
            return .init(tag: tag,
                         art: ItemArt.forSlot(kind: h.kind.rawValue, id: h.id,
                                              card: nil, deckId: c.deckId),
                         name: def?.label ?? h.id,
                         desc: def.map { c.itemDescription($0) } ?? "")
        }
        func itemSide(kind: OldJoker.Holding.Kind, id: String, tag: String) -> OldJokerView.CompareSide {
            itemSide(OldJoker.Holding(kind: kind, id: id), tag: tag)
        }
        func coinSide(_ amount: Int) -> OldJokerView.CompareSide {
            if let coin = ArtBundle.image("pxi-coin") {
                return .init(tag: "GET", art: coin,
                             name: "+\(amount) coins", desc: "")
            }
            return .init(tag: "GET", glyph: "◉",
                         name: "+\(amount) coins", desc: "")
        }
        switch offer {
        case .swap(let taken, let given):
            return [.init(old: itemSide(taken, tag: "GIVE"),
                          new: itemSide(kind: taken.kind, id: given, tag: "GET"))]
        case .blindSwap(let from, _):
            // The hidden side stays hidden — a face-down "?" is the offer.
            return [.init(old: itemSide(from, tag: "GIVE"),
                          new: .init(tag: "GET", glyph: "?",
                                     name: "Something rarer",
                                     desc: ""))]
        case .buyout(let cheap, let cheapCoins, let rich, let richCoins):
            var rows = [OldJokerView.CompareRow(old: itemSide(rich, tag: "GIVE"),
                                                new: coinSide(richCoins))]
            if cheap != rich {
                rows.append(.init(old: itemSide(cheap, tag: "GIVE"),
                                  new: coinSide(cheapCoins)))
            }
            return rows
        case .refund(let options, let values):
            return options.enumerated().map { i, h in
                .init(old: itemSide(h, tag: "GIVE"),
                      new: coinSide(values[safe: i] ?? 0))
            }
        case .freeShop(let taken, _):
            return [.init(old: itemSide(taken, tag: "GIVE"),
                          new: .init(tag: "GET", art: MapArt.shopStall(),
                                     name: "Free shop",
                                     desc: "All items in the next shop are free."))]
        case .jokerForPillars(let pillars):
            // ONE row for the whole trade: every Pillar named on the left,
            // the star on the right — N rows would read as N Jokers.
            let names = pillars.map { c.label($0) }.joined(separator: " + ")
            guard let first = pillars.first else { return [] }
            let firstDef = c.holdingDef(first)
            return [.init(old: .init(tag: "GIVE",
                                     art: ItemArt.forSlot(kind: "pillar", id: first.id,
                                                          card: nil, deckId: c.deckId),
                                     name: pillars.count == 1 ? (firstDef?.label ?? first.id)
                                                              : "All \(pillars.count) Pillars",
                                     desc: names),
                          new: .init(tag: "GET",
                                     art: CardArt.image(CardArt.Face(label: "★", suit: "★", kind: .joker),
                                                        scale: .half),
                                     name: "★ Joker",
                                     desc: "Always a correct call"))]
        default:
            return []   // cards, coins and routes — nothing equipped changes hands
        }
    }

    /// The buttons, in order. DECLINE is always last and always present —
    /// except on a collection, which is not an offer.
    static func options(for offer: OldJoker.Offer, in c: CampaignState) -> [OldJokerView.Option] {
        var out: [OldJokerView.Option] = []
        switch offer {
        case .buyout(let cheap, let cheapCoins, let rich, let richCoins):
            out.append(.init(label: "SELL \(c.label(rich).uppercased())", detail: "+\(richCoins) coins",
                             role: .gold, choice: .takeRich))
            // One item, one price. A second button naming the SAME item for
            // less is a choice nobody would ever take.
            if cheap != rich {
                out.append(.init(label: "SELL \(c.label(cheap).uppercased())", detail: "+\(cheapCoins) coins",
                                 role: .plain, choice: .takeCheap))
            }
        case .swap:
            out.append(.init(label: "TRADE", detail: nil, role: .cta, choice: .accept))
        case .purge(let n, let curses):
            out.append(.init(label: "PURGE \(n)", detail: "\(curses.count) others get cursed", role: .danger, choice: .accept))
        case .ride(_, _, let cost):
            // He makes the offer whether or not you can pay it. Short of the
            // fare, GET IN is shown DEAD — the lift is a thing you're watching
            // leave, not a thing that was never on the table.
            let canPay = c.coins >= cost
            out.append(.init(label: "GET IN",
                             detail: canPay ? "−\(cost) coins" : "you have \(c.coins), the fare is \(cost)",
                             role: canPay ? .cta : .plain, choice: .accept,
                             enabled: canPay))
        case .cut(let cost):
            out.append(.init(label: "LET HIM PICK", detail: "free", role: .plain, choice: .accept))
            out.append(.init(label: "PICK IT YOURSELF", detail: "\(cost) coins",
                             role: c.coins >= cost ? .gold : .plain, choice: .payToChoose))
        case .marker(let coins, _):
            out.append(.init(label: "TAKE THE MARKER", detail: "+\(coins) coins now",
                             role: .gold, choice: .accept))
        case .blindSwap:
            out.append(.init(label: "ACCEPT", detail: nil, role: .cta, choice: .accept))
        case .twoDoors:
            out.append(.init(label: "LEFT DOOR", detail: nil, role: .plain, choice: .left))
            out.append(.init(label: "RIGHT DOOR", detail: nil, role: .plain, choice: .right))
        case .insurance(let cost):
            out.append(.init(label: "PAY \(cost)", detail: "charges the Same shield",
                             role: c.coins >= cost ? .gold : .plain, choice: .accept))
        case .refund(let options, let values):
            for (i, h) in options.enumerated() {
                out.append(.init(label: "SELL \(c.label(h).uppercased())",
                                 detail: "+\(values[safe: i] ?? 0) coins",
                                 role: .gold, choice: .pick(i)))
            }
        case .collect:
            // No decline: this is a collection, not a conversation.
            out.append(.init(label: "PAY UP", detail: nil, role: .danger, choice: .accept))
            return out
        case .freeShop(let taken, _):
            out.append(.init(label: "HAND IT OVER", detail: "Give \(c.label(taken))",
                             role: .cta, choice: .accept))
        case .purgeReset(let from, let to, let cost):
            out.append(.init(label: cost > 0 ? "HALVE IT · \(cost)" : "HALVE IT",
                             detail: "\(from) → \(to) · steeper after",
                             role: c.coins >= cost ? .gold : .plain, choice: .accept,
                             enabled: c.coins >= cost))
        case .eights(_, let to, let affected):
            out.append(.init(label: "COME TO THE MIDDLE",
                             detail: "\(affected) card\(affected == 1 ? "" : "s") → \(to)",
                             role: .cta, choice: .accept))
        case .thirsty:
            // The amount is chosen on the modal's own stepper, and GIVE HIM
            // NOTHING is already the refusal — so this offer takes NO decline
            // row. Two ways to say no, with different consequences (nothing =
            // he comes back angry; walk away = he never came), was a trap.
            return out
        case .thirstReturn(let paid, _):
            // A promise being kept — like a collection, there is no declining it.
            out.append(.init(label: paid > 0 ? "TAKE THEM" : "FACE HIM",
                             detail: nil, role: paid > 0 ? .cta : .danger, choice: .accept))
            return out
        case .duplicate:
            // No sub-line (v6.52): the offer text already warns about the curse.
            out.append(.init(label: "COPY A CARD", detail: nil,
                             role: .cta, choice: .accept))
        case .jokerForPillars:
            out.append(.init(label: "TAKE THE JOKER",
                             detail: "Lose your pillars",
                             role: .cta, choice: .accept))
        }
        out.append(.init(label: "WALK AWAY", detail: nil, role: .plain, choice: .decline))
        return out
    }

    /// What he says after it is done.
    static func closingLine(for result: OldJoker.Result) -> String {
        switch result.key {
        case "collect": return "Debts settled. For now."
        case "thirsty": return result.good ? "Then you." : "Right. Nothing it is."
        default:
            return result.headline == "You keep walking"
                ? "He shuffles himself back into the dark."
                : "He tips a corner of himself at you."
        }
    }
}

extension CampaignState {
    /// Player-facing name for a holding.
    func label(_ h: OldJoker.Holding) -> String { holdingLabel(h) }
    func label(kind: OldJoker.Holding.Kind, id: String) -> String { labelOf(kind: kind, id: id) }
}
