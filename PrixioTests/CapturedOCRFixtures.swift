import CoreGraphics
import Foundation
@testable import Prixio

enum CapturedOCRFixtures {
    static func cadburyShelfTagObservations() -> [OCRTextObservation] {
        [
            observation("99$", confidence: 1.0, x: 0.147, y: 0.002, width: 0.039, height: 0.095),
            observation("Саботи", confidence: 0.3, x: 0.089, y: 0.095, width: 0.022, height: 0.087),
            observation("Min", confidence: 0.5, x: 0.108, y: 0.130, width: 0.038, height: 0.118),
            observation("E99$", confidence: 1.0, x: 0.141, y: 0.127, width: 0.043, height: 0.133),
            observation("Сабвичу", confidence: 0.3, x: 0.092, y: 0.266, width: 0.020, height: 0.079),
            observation("Mihi", confidence: 0.5, x: 0.114, y: 0.297, width: 0.029, height: 0.104),
            observation("E09S", confidence: 1.0, x: 0.149, y: 0.299, width: 0.030, height: 0.110),
            observation("Даббичи", confidence: 0.3, x: 0.087, y: 0.411, width: 0.022, height: 0.074),
            observation("Mini", confidence: 0.5, x: 0.113, y: 0.449, width: 0.027, height: 0.095),
            observation("Eggs", confidence: 1.0, x: 0.131, y: 0.448, width: 0.044, height: 0.105),
            observation("CANDY / FRIANDI", confidence: 1.0, x: 0.233, y: 0.351, width: 0.004, height: 0.025),
            observation("unh", confidence: 0.5, x: 0.111, y: 0.594, width: 0.025, height: 0.070),
            observation("Egg", confidence: 1.0, x: 0.126, y: 0.587, width: 0.045, height: 0.083),
            observation("Alri", confidence: 0.5, x: 0.112, y: 0.713, width: 0.022, height: 0.087),
            observation("E998", confidence: 1.0, x: 0.142, y: 0.712, width: 0.028, height: 0.095),
            observation("Eggs,", confidence: 1.0, x: 0.119, y: 0.838, width: 0.051, height: 0.130),
            observation("Mil", confidence: 0.5, x: 0.404, y: 0.002, width: 0.025, height: 0.050),
            observation("Cadbut", confidence: 0.3, x: 0.378, y: 0.118, width: 0.017, height: 0.070),
            observation("Mine", confidence: 1.0, x: 0.397, y: 0.141, width: 0.031, height: 0.112),
            observation("Забвичи,", confidence: 0.3, x: 0.378, y: 0.260, width: 0.025, height: 0.072),
            observation("Mini", confidence: 1.0, x: 0.392, y: 0.287, width: 0.032, height: 0.099),
            observation("(E99s'", confidence: 0.5, x: 0.421, y: 0.120, width: 0.044, height: 0.155),
            observation("E99Ş", confidence: 0.5, x: 0.415, y: 0.281, width: 0.043, height: 0.116),
            observation("Сабвич", confidence: 0.3, x: 0.372, y: 0.397, width: 0.017, height: 0.066),
            observation("Mifi", confidence: 1.0, x: 0.382, y: 0.422, width: 0.043, height: 0.099),
            observation("E995'", confidence: 0.5, x: 0.406, y: 0.421, width: 0.049, height: 0.119),
            observation("Cadbury Chocolate Mini", confidence: 1.0, x: 0.521, y: 0.408, width: 0.015, height: 0.116),
            observation("Eggs Easter 875 g", confidence: 1.0, x: 0.531, y: 0.408, width: 0.014, height: 0.086),
            observation("SAVE", confidence: 1.0, x: 0.578, y: 0.419, width: 0.028, height: 0.092),
            observation("THIS WEEK", confidence: 1.0, x: 0.599, y: 0.424, width: 0.017, height: 0.089),
            observation("Cadbury", confidence: 0.3, x: 0.366, y: 0.672, width: 0.013, height: 0.058),
            observation("Mini", confidence: 1.0, x: 0.377, y: 0.690, width: 0.034, height: 0.097),
            observation("Eggs'", confidence: 0.5, x: 0.398, y: 0.692, width: 0.039, height: 0.107),
            observation("Сабвич,", confidence: 0.3, x: 0.350, y: 0.819, width: 0.022, height: 0.070),
            observation("Min", confidence: 1.0, x: 0.369, y: 0.847, width: 0.029, height: 0.079),
            observation("E995", confidence: 1.0, x: 0.391, y: 0.843, width: 0.038, height: 0.090),
            observation("22%°", confidence: 1.0, x: 0.517, y: 0.614, width: 0.016, height: 0.037),
            observation("AD Exp Mar 04, 2026", confidence: 1.0, x: 0.533, y: 0.548, width: 0.009, height: 0.061),
            observation("1799", confidence: 1.0, x: 0.556, y: 0.523, width: 0.050, height: 0.113),
            observation("- SAVE", confidence: 1.0, x: 0.605, y: 0.527, width: 0.013, height: 0.054),
            observation("$5.00 ea", confidence: 1.0, x: 0.605, y: 0.605, width: 0.009, height: 0.047),
            observation("ini", confidence: 1.0, x: 0.635, y: 0.002, width: 0.026, height: 0.056),
            observation("Miur", confidence: 0.3, x: 0.628, y: 0.103, width: 0.033, height: 0.099),
            observation("\"Eggs", confidence: 1.0, x: 0.649, y: 0.071, width: 0.040, height: 0.137),
            observation("Qadouro", confidence: 0.3, x: 0.600, y: 0.257, width: 0.020, height: 0.075),
            observation("Mind", confidence: 0.5, x: 0.614, y: 0.283, width: 0.025, height: 0.087),
            observation("Egg$", confidence: 0.5, x: 0.629, y: 0.260, width: 0.050, height: 0.125),
            observation("Mill", confidence: 0.5, x: 0.592, y: 0.806, width: 0.019, height: 0.076),
            observation("Eggs", confidence: 1.0, x: 0.603, y: 0.800, width: 0.033, height: 0.085),
            observation("Сабвим,", confidence: 0.3, x: 0.569, y: 0.898, width: 0.023, height: 0.068),
            observation("EggS", confidence: 1.0, x: 0.603, y: 0.919, width: 0.032, height: 0.078),
            observation("Сабвичу®", confidence: 0.3, x: 0.799, y: 0.175, width: 0.022, height: 0.070),
            observation("RSHEY'S", confidence: 0.5, x: 0.821, y: 0.001, width: 0.014, height: 0.046),
            observation("M999", confidence: 0.5, x: 0.795, y: 0.549, width: 0.053, height: 0.094),
            observation("Сабвичи", confidence: 0.3, x: 0.961, y: 0.058, width: 0.015, height: 0.048),
            observation("Mint", confidence: 1.0, x: 0.977, y: 0.070, width: 0.022, height: 0.083),
            observation("Mini", confidence: 1.0, x: 0.954, y: 0.196, width: 0.042, height: 0.090),
            observation("Min", confidence: 1.0, x: 0.945, y: 0.305, width: 0.041, height: 0.068),
            observation("209-", confidence: 1.0, x: 0.967, y: 0.312, width: 0.032, height: 0.072),
            observation("Min!", confidence: 1.0, x: 0.966, y: 0.398, width: 0.029, height: 0.080),
            observation("Min", confidence: 1.0, x: 0.954, y: 0.541, width: 0.032, height: 0.071),
            observation("5099", confidence: 0.5, x: 0.969, y: 0.539, width: 0.029, height: 0.079),
            observation("MinI", confidence: 1.0, x: 0.778, y: 0.682, width: 0.035, height: 0.074),
            observation("EggS", confidence: 0.5, x: 0.797, y: 0.676, width: 0.043, height: 0.087),
            observation("Min", confidence: 1.0, x: 0.936, y: 0.665, width: 0.036, height: 0.071),
            observation("Cadbury", confidence: 0.5, x: 0.927, y: 0.754, width: 0.012, height: 0.045),
            observation("Eg95", confidence: 0.5, x: 0.949, y: 0.658, width: 0.052, height: 0.095),
            observation("* MIni", confidence: 1.0, x: 0.929, y: 0.746, width: 0.032, height: 0.091),
            observation("Eggs", confidence: 1.0, x: 0.945, y: 0.758, width: 0.043, height: 0.088),
            observation("Mini", confidence: 1.0, x: 0.758, y: 0.786, width: 0.042, height: 0.081),
            observation("EggS", confidence: 1.0, x: 0.780, y: 0.785, width: 0.047, height: 0.089),
            observation("MIal", confidence: 0.5, x: 0.746, y: 0.907, width: 0.032, height: 0.060)
        ]
    }

    private static func observation(
        _ string: String,
        confidence: Float,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> OCRTextObservation {
        OCRTextObservation(
            string: string,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}
