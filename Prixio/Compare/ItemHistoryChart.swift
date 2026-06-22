import Charts
import SwiftUI

/// A compact price-over-time chart for a single item. Plots each observation as a line+point
/// series and shades the "usual" band (median ± tolerance) when enough history exists.
///
/// `Decimal` is not `Plottable`, so values are converted to `Double` for plotting only — all
/// stored math stays in `Decimal`.
struct ItemHistoryChart: View {
    let history: ItemPriceHistory

    private func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    var body: some View {
        Chart {
            if history.hasUsualBand {
                RectangleMark(
                    yStart: .value("Usual low", double(history.usualLow)),
                    yEnd: .value("Usual high", double(history.usualHigh))
                )
                .foregroundStyle(.green.opacity(0.12))

                RuleMark(y: .value("Usual price", double(history.median)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }

            ForEach(history.timeline, id: \.entryID) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", double(point.price))
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Price", double(point.price))
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: AppCurrency.defaultCode))
        }
        .frame(height: 180)
        .padding(.vertical, 4)
        .accessibilityLabel("Price history chart")
        .accessibilityValue(
            "\(history.observationCount) prices from \(CurrencyFormatter.shared.display(history.lowest.price)) to \(CurrencyFormatter.shared.display(history.highest.price))"
        )
    }
}
