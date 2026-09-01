import UIKit

/// COLORFUL CARDS (v6.96) — the setting's storage + cache-flush chokepoint.
///
/// CRT.swift holds the flag (`CRT.colorfulCards`) and the colour rule
/// (`CRT.suitColor`); this extension owns the UserDefaults pref and the rebake
/// every suit-bearing cache needs on a flip. The baked-art cache keys carry
/// NO colour component, so without this flush a toggled scheme would never
/// reach already-cached faces, glyphs and captions. CRT (in Rendering) can't
/// see the campaign, so the pref rides UserDefaults exactly like the sound
/// pref (`ninelives.pref.sound`, SoundEngine).
public extension CRT {

    /// Boot load (AppDelegate): reads the pref into the flag. The caches are
    /// empty at boot, so no flush is needed here.
    static func loadColorfulCardsPref() {
        colorfulCards = UserDefaults.standard.string(forKey: "ninelives.pref.colorfulCards") == "1"
    }

    /// THE one toggle path: set the flag, persist, flush every suit-bearing
    /// bake cache. Flushing does not recolour LIVE nodes still holding the
    /// old textures — the caller re-syncs the visible screen (the deal scene
    /// via `DealController.refreshAll()`; menu screens rebuild on their next
    /// appear). PixelGlyph.cache keys carry `color.description`, so the inline
    /// glyph cache is self-healing and needs no flush.
    static func setColorfulCards(_ on: Bool) {
        colorfulCards = on
        UserDefaults.standard.set(on ? "1" : "0", forKey: "ninelives.pref.colorfulCards")
        CardArt.flushColorCaches()
        PixelTexture.flushTextCaches()
        ItemArt.flushColorCaches()
        MapArt.flushColorCaches()
    }
}
