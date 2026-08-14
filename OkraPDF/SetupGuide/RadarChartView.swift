import SwiftUI

struct RadarChartSeries: Identifiable {
    let name: String
    let color: Color
    /// One 0…1 value per axis, in the same order as the chart's axes.
    let values: [Double]

    var id: String { name }
}

/// A five-axis spider (radar) chart used to compare parser pairings across the
/// ParseBench capability dimensions. Pure SwiftUI paths — no chart framework.
struct RadarChartView: View {
    let axes: [ParseBenchDimension]
    let series: [RadarChartSeries]
    /// Fraction of the chart radius reserved for axis labels.
    var labelPaddingFraction = 0.16

    private let ringFractions: [Double] = [0.25, 0.5, 0.75, 1.0]

    var body: some View {
        GeometryReader { proxy in
            let layout = RadarLayout(
                size: proxy.size,
                axisCount: axes.count,
                labelPaddingFraction: labelPaddingFraction
            )
            ZStack {
                gridPath(layout: layout)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                spokesPath(layout: layout)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)

                ForEach(series) { item in
                    polygonPath(for: item, layout: layout)
                        .fill(item.color.opacity(0.16))
                    polygonPath(for: item, layout: layout)
                        .stroke(item.color, lineWidth: 2)
                    vertexDots(for: item, layout: layout)
                }

                axisLabels(layout: layout)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func gridPath(layout: RadarLayout) -> Path {
        var path = Path()
        for fraction in ringFractions {
            let ring = polygonPoints(values: Array(repeating: fraction, count: axes.count), layout: layout)
            path.addPolygon(ring)
        }
        return path
    }

    private func spokesPath(layout: RadarLayout) -> Path {
        var path = Path()
        for index in axes.indices {
            path.move(to: layout.center)
            path.addLine(to: layout.point(axisIndex: index, fraction: 1))
        }
        return path
    }

    private func polygonPath(for item: RadarChartSeries, layout: RadarLayout) -> Path {
        var path = Path()
        path.addPolygon(polygonPoints(values: item.values, layout: layout))
        return path
    }

    private func polygonPoints(values: [Double], layout: RadarLayout) -> [CGPoint] {
        axes.indices.map { index in
            let value = index < values.count ? values[index] : 0
            return layout.point(axisIndex: index, fraction: min(max(value, 0), 1))
        }
    }

    private func vertexDots(for item: RadarChartSeries, layout: RadarLayout) -> some View {
        ForEach(Array(axes.indices), id: \.self) { index in
            let value = index < item.values.count ? item.values[index] : 0
            let point = layout.point(axisIndex: index, fraction: min(max(value, 0), 1))
            Circle()
                .fill(item.color)
                .frame(width: 5, height: 5)
                .position(point)
        }
    }

    private func axisLabels(layout: RadarLayout) -> some View {
        ForEach(Array(axes.indices), id: \.self) { index in
            let point = layout.point(axisIndex: index, fraction: 1 + labelPaddingFraction)
            Text(axes[index].title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: layout.labelWidth)
                .fixedSize(horizontal: false, vertical: true)
                .position(point)
        }
    }

    private var accessibilitySummary: String {
        series.map { item in
            let pairs = axes.indices.compactMap { index -> String? in
                guard index < item.values.count else { return nil }
                let percent = Int((item.values[index] * 100).rounded())
                return "\(axes[index].title) \(percent) percent"
            }
            return "\(item.name): " + pairs.joined(separator: ", ")
        }
        .joined(separator: ". ")
    }
}

/// Geometry for a radar chart: vertices on a circle starting at 12 o'clock,
/// clockwise, in axis order.
struct RadarLayout {
    let center: CGPoint
    let radius: Double
    let axisCount: Int
    let labelWidth: Double

    init(size: CGSize, axisCount: Int, labelPaddingFraction: Double) {
        let side = min(size.width, size.height)
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.radius = max((side / 2) / (1 + labelPaddingFraction) - 8, 1)
        self.axisCount = max(axisCount, 3)
        self.labelWidth = max(side * labelPaddingFraction * 1.6, 56)
    }

    func point(axisIndex: Int, fraction: Double) -> CGPoint {
        let angle = (Double(axisIndex) / Double(axisCount)) * 2 * .pi - .pi / 2
        return CGPoint(
            x: center.x + cos(angle) * radius * fraction,
            y: center.y + sin(angle) * radius * fraction
        )
    }
}

private extension Path {
    mutating func addPolygon(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
        closeSubpath()
    }
}
