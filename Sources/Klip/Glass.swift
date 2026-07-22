import AppKit
import SwiftUI

/// Press feedback for custom (`.plain`/`.borderless`) buttons that don't get AppKit's native
/// press dip. Apple's first fluid-interface principle: respond on press-DOWN, instantly. The dip
/// rides a critically-damped spring (no overshoot) so it feels physical, not scripted. Respects
/// Reduce Motion (the spring degrades to an instant state change there automatically).
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: configuration.isPressed)
    }
}

/// Shared helpers for real behind-window vibrancy ("glass").
@MainActor
enum GlassMask {
    /// Rounded-corner mask for an NSVisualEffectView.
    ///
    /// CRITICAL: never round a visual-effect view with `wantsLayer` + `layer.cornerRadius` +
    /// `masksToBounds`. `.behindWindow` blending works by the window server compositing the material
    /// through the view's `maskImage`; forcing the view into its own clipped backing layer composites
    /// it off-screen instead and collapses the glass to flat opaque gray — regardless of the material.
    /// A resizable rounded-rect `maskImage` gives the same corners while keeping the blur alive.
    static func rounded(_ radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

/// The half of the glass recipe every surface shares: the specular sheen, plus the
/// Reduce-Transparency / Increase-Contrast opaque fallback. Sits over the backdrop
/// NSVisualEffectView and under the content — floating panels add a rim on top of this,
/// titled windows don't.
///
/// Its layer background is CLEAR while glass is live: any non-clear layer over an
/// NSVisualEffectView blocks the vibrancy. It only goes opaque as the accessibility floor,
/// where the glass is meant to be gone anyway.
private final class GlassSheenView: NSView {
    private let sheen = CAGradientLayer()
    /// Runs after every recipe pass with the resolved state, so an owner can drive the parts that
    /// aren't shared (GlassPanelView's rim) off the same (dark, reduce) resolution.
    var onRecipe: ((_ dark: Bool, _ reduce: Bool) -> Void)?

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        // Specular sheen — the "mirror" band: a soft diagonal highlight from the top-left, like
        // light reflecting off the glass (Liquid Glass's Highlight layer). This is what makes the
        // surface read as glass even over plain white content, where blur alone shows nothing.
        // Directional and edge-weighted — NOT a flat white veil (which would just raise the floor).
        sheen.type = .axial
        sheen.startPoint = CGPoint(x: 0, y: 1)      // top-left (macOS layer coords: y-up)
        sheen.endPoint = CGPoint(x: 0.65, y: 0.1)   // fades out ~2/3 across, light at ≈ -60°
        sheen.cornerRadius = cornerRadius
        sheen.cornerCurve = .continuous
        sheen.masksToBounds = true
        layer?.addSublayer(sheen)

        // NSWorkspace posts this on its OWN notification center, not on `.default`.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applyRecipe),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared)
        applyRecipe()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Decoration must never intercept clicks: the sheen sits above the backdrop and, in the panel,
    /// the content sits above it — but the rim above that would still swallow presses without this
    /// (a dead Cancel button). Same rule everywhere.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        sheen.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyRecipe()
    }

    /// The measured CoreUI recipe (see references/apple-glass/DESIGN-BRIEF.md §3.2).
    @objc func applyRecipe() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if reduce {
            // System materials go fully opaque here; so do we (the accessibility floor).
            sheen.isHidden = true
            layer?.backgroundColor = NSColor(white: dark ? 0.12 : 0.8784, alpha: 1).cgColor
        } else {
            // NO extra tint: the system material already applies Apple's full recipe (floor +
            // darken ceiling + saturation) internally. Measured in the glass lab: raw .popover+mask
            // converges to the same value as a REAL Finder menu over the same backdrop (Δ≈-9 vs
            // +15, both toward ~188); adding the CoreUI tint on top double-applies it and lands
            // ~20 too dark.
            layer?.backgroundColor = NSColor.clear.cgColor
            sheen.isHidden = false
            sheen.colors = dark
                ? [NSColor(white: 1, alpha: 0.10).cgColor,
                   NSColor(white: 1, alpha: 0.03).cgColor,
                   NSColor.clear.cgColor]
                : [NSColor(white: 1, alpha: 0.28).cgColor,
                   NSColor(white: 1, alpha: 0.08).cgColor,
                   NSColor.clear.cgColor]
            sheen.locations = [0, 0.3, 0.6]
        }
        onRecipe?(dark, reduce)
    }
}

/// A floating glass surface implementing Apple's real material recipe (references/apple-glass):
///
///   backdrop  — NSVisualEffectView (.popover, .behindWindow, .active) rounded via maskImage
///   sheen     — GlassSheenView: the specular highlight + the accessibility opaque fallback
///   content   — hosted above the sheen (fills + vibrancy only; never a second effect view)
///   rim       — where glass is actually defined: concentric strokes, light-catching edge.
///
/// Adapts to the effective appearance (light/dark) and goes fully opaque under Reduce
/// Transparency / Increase Contrast, mirroring the system materials' fallback.
final class GlassPanelView: NSView {
    /// Decoration that must never intercept clicks: the rim sits ABOVE the hosted content,
    /// so without this it'd swallow every press (a dead Cancel button).
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let fx = NSVisualEffectView()
    private let sheenView: GlassSheenView
    private let rimView = PassthroughView()
    private let rimOuter = CALayer()
    private let rimInner = CALayer()
    private let radius: CGFloat
    private weak var content: NSView?

    init(frame: NSRect, radius: CGFloat, material: NSVisualEffectView.Material = .popover) {
        self.radius = radius
        self.sheenView = GlassSheenView(cornerRadius: radius)
        super.init(frame: frame)

        fx.material = material
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.isEmphasized = false
        fx.maskImage = GlassMask.rounded(radius)
        fx.frame = bounds
        fx.autoresizingMask = [.width, .height]
        addSubview(fx)

        sheenView.frame = bounds
        sheenView.autoresizingMask = [.width, .height]
        addSubview(sheenView)

        rimView.wantsLayer = true
        rimView.frame = bounds
        rimView.autoresizingMask = [.width, .height]
        rimOuter.borderWidth = 0.5
        rimInner.borderWidth = 1
        rimOuter.cornerCurve = .continuous
        rimInner.cornerCurve = .continuous
        rimView.layer?.addSublayer(rimOuter)
        rimView.layer?.addSublayer(rimInner)
        addSubview(rimView)

        // The rim is the panel-only half of the recipe; the sheen view already tracks appearance
        // and accessibility changes, so hang the rim off its pass instead of observing twice.
        sheenView.onRecipe = { [weak self] dark, reduce in self?.applyRim(dark: dark, reduce: reduce) }
        sheenView.applyRecipe()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Installs the hosted content between the sheen and the rim.
    ///
    /// The content is clipped to the panel's rounded shape: an NSHostingView is a plain rectangle,
    /// so without this its square backing shows past the glass corners as a white box. Clipping the
    /// CONTENT is safe — unlike clipping the effect view, which would break behind-window blending.
    func setContent(_ view: NSView) {
        content?.removeFromSuperview()
        content = view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        addSubview(view, positioned: .below, relativeTo: rimView)
    }

    override func layout() {
        super.layout()
        // Concentric rim: outer contour hugs the panel edge at r + its own width; inner specular
        // stroke sits just inside at r (inner_radius = outer_radius − stroke, Apple's concentricity).
        rimOuter.frame = rimView.bounds
        rimOuter.cornerRadius = radius
        rimInner.frame = rimView.bounds.insetBy(dx: 0.5, dy: 0.5)
        rimInner.cornerRadius = max(0, radius - 0.5)
    }

    /// The panel-only half of the recipe, driven by GlassSheenView's pass.
    private func applyRim(dark: Bool, reduce: Bool) {
        // The sheen view's opaque fallback already covers the backdrop under Reduce Transparency;
        // hide it too so no live material bleeds at the mask edge.
        fx.isHidden = reduce
        if reduce {
            rimOuter.borderColor = NSColor(white: dark ? 1 : 0, alpha: 1).cgColor
            rimOuter.borderWidth = 1
            rimInner.isHidden = true
            return
        }

        rimOuter.borderWidth = 0.5
        rimInner.isHidden = false
        if dark {
            rimOuter.borderColor = NSColor(white: 0, alpha: 0.8).cgColor
            rimInner.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        } else {
            rimOuter.borderColor = NSColor(white: 0, alpha: 0.10).cgColor   // faint contour so the edge reads over white content
            rimInner.borderColor = NSColor(white: 1, alpha: 0.5).cgColor    // specular inner edge (light catching the glass)
        }
    }
}

/// Native macOS "glass" chrome for auxiliary windows (Welcome, Guide, Upload, Preferences):
/// a behind-window translucent material running edge to edge under a transparent titlebar,
/// so they match the history panel / HUD look instead of a flat opaque window.
@MainActor
enum Glass {
    /// Replaces the window's content view with a glass background hosting `root`, and makes
    /// the titlebar transparent over it. SwiftUI content keeps respecting the titlebar via
    /// the hosting view's safe area.
    ///
    /// Same recipe as GlassPanelView, minus two parts that windows don't need:
    ///   - NO rim. The window frame already draws its own edge and shadow; a second stroke just
    ///     inside it would double the line instead of defining it.
    ///   - NO maskImage / corner work. These are TITLED windows — the frame clips the corners.
    ///     (Borderless panels must round the material via maskImage; see GlassMask.)
    static func install<V: View>(_ root: V, in window: NSWindow,
                                 material: NSVisualEffectView.Material = .underWindowBackground) {
        let fx = NSVisualEffectView()
        fx.material = material
        fx.blendingMode = .behindWindow
        // .active, not .followsWindowActiveState: the panels never grey out on deactivation, and a
        // background that flips to inactive grey next to them reads as a bug, not as a state.
        fx.state = .active

        // Sheen + accessibility fallback, shared with GlassPanelView. Below the content, as there.
        // It goes opaque under Reduce Transparency and covers `fx` edge to edge, so `fx` itself
        // needs no hiding here (unlike the panel, where the two are siblings).
        let sheen = GlassSheenView(cornerRadius: 0)
        sheen.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(sheen)

        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([
            sheen.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            sheen.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            sheen.topAnchor.constraint(equalTo: fx.topAnchor),
            sheen.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            host.topAnchor.constraint(equalTo: fx.topAnchor),
            host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentView = fx
    }
}
