import UIKit
import GameCore

/// WHO delivers a "?" node's news. The Old Joker deals; these two just hand
/// things over — THE BEHEADED QUEEN gives away everything good (she was
/// purged from a deck once, lost her head, and has nothing left to lose),
/// and JUST A TWO delivers everything bad (a two gets stepped on its whole
/// life, and it has decided that is everyone else's fault).
///
/// Kept beside OldJokerCopy for the same reason it is: voice lives apart
/// from logic, so the writing can be edited without touching a rule.
enum MysteryCast {

    struct Presenter {
        let name: String
        let art: UIImage
        let line: String
    }

    /// The presenter for a mystery outcome. (The Old Joker's own chained
    /// reveals bypass this — he stays the voice inside his frame.)
    ///
    /// The Windfall is the one boon the TWO hands over: more cards is deck
    /// bloat, and deck bloat is exactly the kind of thing a two would wish
    /// on you. (A Joker stays the Queen's — that card is strictly a gift.)
    static func presenter(for outcome: MysteryOutcome) -> Presenter? {
        return outcome.good && outcome.key != "cards"
            ? Presenter(name: "The Beheaded Queen",
                        art: ItemArt.beheadedQueen(scale: 4),
                        line: queenLine(outcome.key))
            : Presenter(name: "Just a Two",
                        art: ItemArt.justATwo(scale: 4),
                        line: twoLine(outcome.key))
    }

    /// Her house style: gentle, past-tense, generous. She never explains the
    /// mechanics (the outcome panel does that) and she never mourns out loud
    /// — the missing head does the talking.
    private static func queenLine(_ key: String) -> String {
        switch key {
        case "coinBonus":
            return "Take them. I stopped counting what I was owed a long time ago."
        case "joker":
            return "He never took sides when it mattered. Maybe he'll take yours."
        case "stickerPack":
            return "A little shine. It never saved me. May it fit you better."
        case "freeRemoval":
            return "Let one go. Kinder when it's your own choice. I would know."
        case "stickerStrip":
            return "Peel it off. Whatever they stuck to you, you don't have to keep."
        case "store":
            return "The shopkeep still owes me a kindness. Go in. I told them you'd come."
        case "priceOne":
            return "I told the shopkeep what a crown is worth. Everything's a coin till they restock."
        case "freeRefresh":
            return "Make them set the shelf again. Tell them the Queen is paying."
        case "freeRedeal":
            return "Take the hand back once, on me. Everyone deserves a second dealing."
        case "shieldCharge":
            return "A shield. I'd have kept mine up, if I'd known which day to."
        case "coinDouble":
            return "Whatever you've saved, I'll match it. It was all going spare anyway."
        case "giftCard":
            return "I dressed this one myself. Give it a better life than mine."
        default:
            return "What's mine is yours. I can't hold onto anything anymore."
        }
    }

    /// Its house style: short, bitter, second person. It is never sorry.
    private static func twoLine(_ key: String) -> String {
        switch key {
        case "coinLoss":
            return "Everyone takes from a two. Today a two takes from you."
        case "cards":
            return "More cards. Congratulations. A fat deck never saved anyone."
        case "cursedSticker":
            return "You get stepped on your whole life, you start leaving marks."
        case "ambush":
            return "Nobody ever backs down from a two. Let's see how you do surrounded."
        case "stickerTheft":
            return "Shiny little things. You didn't earn them either."
        case "itemTheft":
            return "You'll do without. Twos always do."
        case "priceDouble":
            return "I had a word with the shop. For once the prices aren't MY problem."
        case "shieldDrain":
            return "A shield. Must be nice. Was nice."
        case "mammaLie":
            return "You believed that? A two doesn't know ANYBODY."
        case "twoGame":
            return "One card. One call. Twos always know."
        default:
            return "Don't look at me like that. The world started it."
        }
    }
}
