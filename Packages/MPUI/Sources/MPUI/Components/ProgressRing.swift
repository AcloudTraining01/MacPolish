import SwiftUI

public struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let accentColor: Color
    let size: CGFloat

    public init(
        progress: Double,
        lineWidth: CGFloat = 6,
        accentColor: Color = MPColors.cleanupAccent,
        size: CGFloat = 80
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.accentColor = accentColor
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accentColor.opacity(0.6), accentColor]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            if progress > 0.02 {
                Circle()
                    .fill(accentColor)
                    .frame(width: lineWidth, height: lineWidth)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * progress - 90))
                    .shadow(color: accentColor.opacity(0.5), radius: 3)
                    .animation(.easeInOut(duration: 0.5), value: progress)
            }
        }
        .frame(width: size, height: size)
    }
}

public struct IndeterminateSpinner: View {
    @State private var rotation: Double = 0
    let accentColor: Color
    let size: CGFloat

    public init(accentColor: Color = MPColors.aiAccent, size: CGFloat = 32) {
        self.accentColor = accentColor
        self.size = size
    }

    public var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [accentColor.opacity(0), accentColor]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
