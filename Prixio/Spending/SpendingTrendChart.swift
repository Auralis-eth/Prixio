import Charts
import SwiftUI

/// Spending over time: monthly spending as bars with an income reference line. `Decimal` is not
/// `Plottable`, so values are converted to `Double` for plotting only.
struct SpendingTrendChart: View {
    let trend: [SpendingTrendPoint]

    private func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    var body: some View {
        Chart {
            ForEach(trend) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Spending", double(point.spending))
                )
                .foregroundStyle(Color.accentColor.opacity(0.7))

                if point.income > 0 {
                    LineMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Income", double(point.income))
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: AppCurrency.defaultCode))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.narrow))
            }
        }
        .frame(height: 180)
        .padding(.vertical, 4)
        .accessibilityLabel("Spending over time")
    }
}
