//
//  SpineLogoView.swift
//  WellRead
//
//  SPINE v2 brand mark (reader + open book). The asset is a single-color
//  template image, so it tints like an SF Symbol — ink on paper in light
//  mode, paper on CRT-black in dark.
//

import SwiftUI

/// Static v2 logo. Scales to fit whatever frame you give it.
struct SpineLogoView: View {
    var size: CGFloat = 96
    var tint: Color = Theme.textPrimary

    var body: some View {
        Image("SpineLogoV2")
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

/// Loading-state logo: whips through a full turn, decelerates to a stop,
/// takes a breath (soft scale pulse), then spins again. Honors Reduce
/// Motion by swapping the spin for a gentle opacity pulse.
struct SpineLogoLoadingView: View {
    var size: CGFloat = 132
    var tint: Color = Theme.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct SpinState {
        var angle = 0.0
        var scale = 1.0
        var opacity = 1.0
    }

    var body: some View {
        SpineLogoView(size: size, tint: tint)
            .keyframeAnimator(initialValue: SpinState(), repeating: true) { view, state in
                view
                    .rotationEffect(.degrees(reduceMotion ? 0 : state.angle))
                    .scaleEffect(reduceMotion ? 1 : state.scale)
                    .opacity(reduceMotion ? state.opacity : 1)
            } keyframes: { _ in
                // One 2.8s cycle: spin launches fast and coasts to a stop
                // (1.5s), then the mark breathes while at rest (1.3s).
                // 360° ≡ 0°, so the loop restarts seamlessly.
                KeyframeTrack(\.angle) {
                    CubicKeyframe(360, duration: 1.5, startVelocity: 650, endVelocity: 0)
                    LinearKeyframe(360, duration: 1.3)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1.0, duration: 1.5)
                    CubicKeyframe(1.07, duration: 0.65)
                    CubicKeyframe(1.0, duration: 0.65)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 1.5)
                    CubicKeyframe(0.45, duration: 0.65)
                    CubicKeyframe(1.0, duration: 0.65)
                }
            }
    }
}

/// Full-screen branded loading state — themed page with the animated mark.
/// Used at app open (auth resolution) and anywhere else the whole screen waits.
struct SpineLoadingScreen: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            SpineLogoLoadingView()
        }
    }
}

#Preview("Loading screen") {
    SpineLoadingScreen()
}

#Preview("Static mark") {
    ZStack {
        Theme.background.ignoresSafeArea()
        SpineLogoView()
    }
}
