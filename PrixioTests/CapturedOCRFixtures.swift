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

    static func miniCucumberObservations() -> [OCRTextObservation] {
        [
            observation("MINI CUCUMBER", confidence: 1.0, x: 0.430, y: 0.323, width: 0.153, height: 0.015),
            observation("Perfect for snacking", confidence: 1.0, x: 0.434, y: 0.305, width: 0.087, height: 0.009),
            observation("High water content helps to keep you", confidence: 1.0, x: 0.434, y: 0.295, width: 0.155, height: 0.009),
            observation("hydrated", confidence: 1.0, x: 0.436, y: 0.286, width: 0.041, height: 0.007),
            observation("$4.00", confidence: 1.0, x: 0.469, y: 0.266, width: 0.066, height: 0.022)
        ]
    }

    static func bananasStage4Observations() -> [OCRTextObservation] {
        [
            observation(".99", confidence: 0.98, x: 0.401, y: 0.331, width: 0.048, height: 0.040),
            observation(") 247", confidence: 0.91, x: 0.446, y: 0.302, width: 0.070, height: 0.052),
            observation("545 / Kg", confidence: 0.95, x: 0.462, y: 0.270, width: 0.121, height: 0.047),
            observation("Bananas Stage 4 PLU 4011", confidence: 0.97, x: 0.358, y: 0.221, width: 0.278, height: 0.051),
            observation(".79.-", confidence: 0.89, x: 0.397, y: 0.190, width: 0.075, height: 0.041)
        ]
    }

    static func sparseGrowerObservations() -> [OCRTextObservation] {
        [
            observation("1908.0", confidence: 0.87, x: 0.349, y: 0.355, width: 0.099, height: 0.044),
            observation("HGROWER. COM YE", confidence: 0.93, x: 0.301, y: 0.302, width: 0.246, height: 0.045),
            observation("299", confidence: 0.96, x: 0.438, y: 0.247, width: 0.051, height: 0.041),
            observation("299", confidence: 0.94, x: 0.436, y: 0.197, width: 0.052, height: 0.042)
        ]
    }

    static func butterShelfCompetingTagObservations() -> [OCRTextObservation] {
        [
            observation("A20-RO4", confidence: 0.5, x: 0.05232558111917209, y: 0.454941860896497, width: 0.031007751585945244, height: 0.008720929660494314),
            observation("EDV", confidence: 0.5, x: 0.09883720964873331, y: 0.4549418605465696, width: 0.015503875792972632, height: 0.005813953422364793),
            observation("Comp Butter Salted", confidence: 1.0, x: 0.05176881948831763, y: 0.44508062418756866, width: 0.08624565285980387, height: 0.011925028430091023),
            observation("PK 50", confidence: 0.5, x: 0.13953488432529376, y: 0.452034884001572, width: 0.017441859320988712, height: 0.007290512796432336),
            observation("454 g", confidence: 1.0, x: 0.05038759756685362, y: 0.4360119047229002, width: 0.019379844110478793, height: 0.007302048660459914),
            observation("599", confidence: 1.0, x: 0.12984496215139593, y: 0.42151162820510446, width: 0.05426356401393023, height: 0.02325581368945895),
            observation("09 0506950", confidence: 1.0, x: 0.04651162906058323, y: 0.4171511631251792, width: 0.04457364258942782, height: 0.008720929660494425),
            observation("CANADA", confidence: 0.3, x: 0.7054263578433329, y: 0.9520348843719352, width: 0.046511624855969935, height: 0.01889534791310632),
            observation("Comp Butter Unsalted", confidence: 1.0, x: 0.6874287095680477, y: 0.8935328827678447, width: 0.0980107948262855, height: 0.012352839348808153),
            observation("Product of Canada", confidence: 1.0, x: 0.6836016684002378, y: 0.8871153846554898, width: 0.06883124699668286, height: 0.010491950171334308),
            observation("250 G", confidence: 1.0, x: 0.6841085283965148, y: 0.8735119047410688, width: 0.02131782763849488, height: 0.007302048660459914),
            observation("4УУOU", confidence: 0.3, x: 0.6821705427227844, y: 0.869186046646393, width: 0.019379842849004847, height: 0.0029069764746559867),
            observation("/100G", confidence: 1.0, x: 0.7073643422356197, y: 0.866279069999634, width: 0.023255812427985023, height: 0.0072674415414295535),
            observation("5574253713", confidence: 1.0, x: 0.6821705413986346, y: 0.8604651163840817, width: 0.04263566032288568, height: 0.0072674415414295535),
            observation("VY 0483561", confidence: 1.0, x: 0.6802325610278485, y: 0.8561046512975558, width: 0.03488371864197748, height: 0.003022332867932742),
            observation("Scene", confidence: 1.0, x: 0.6841085293382492, y: 0.812500000006446, width: 0.04263565527698987, height: 0.010174418252612005),
            observation("4°9", confidence: 1.0, x: 0.7499999996512187, y: 0.8604651167764579, width: 0.04263566032288568, height: 0.02034883650522379),
            observation("FS Exp Mar 18, 2026", confidence: 1.0, x: 0.755504375523564, y: 0.8495360912785237, width: 0.07431519725335345, height: 0.009763447065202047),
            observation("Buy", confidence: 1.0, x: 0.6879844960833614, y: 0.7630813955621947, width: 0.029069766796455232, height: 0.008720929660494425),
            observation("1", confidence: 0.5, x: 0.6957364344423415, y: 0.7500000003587063, width: 0.009689922055239442, height: 0.008720929660494425),
            observation("50", confidence: 1.0, x: 0.7616279066744889, y: 0.7601744188315429, width: 0.019379845371952698, height: 0.010174418252611894),
            observation("PTS", confidence: 1.0, x: 0.7538759691224864, y: 0.7470930234691715, width: 0.02713178200696509, height: 0.008720929660494314)
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
