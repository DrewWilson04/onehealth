import Foundation

/// Small, dependency-free statistics toolkit for the insights engine.
public enum Stats {
    public static func mean(_ x: [Double]) -> Double { x.isEmpty ? .nan : x.reduce(0, +) / Double(x.count) }

    public static func variance(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        return x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
    }

    public static func sd(_ x: [Double]) -> Double { sqrt(variance(x)) }

    /// Average ranks (ties share the mean rank), 1-based.
    public static func ranks(_ x: [Double]) -> [Double] {
        let idx = x.indices.sorted { x[$0] < x[$1] }
        var r = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < idx.count {
            var j = i
            while j + 1 < idx.count && x[idx[j + 1]] == x[idx[i]] { j += 1 }
            let avg = Double(i + j) / 2 + 1
            for k in i...j { r[idx[k]] = avg }
            i = j + 1
        }
        return r
    }

    public static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, x.count > 2 else { return .nan }
        let mx = mean(x), my = mean(y)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) { sxy += (a - mx) * (b - my); sxx += (a - mx) * (a - mx); syy += (b - my) * (b - my) }
        guard sxx > 0, syy > 0 else { return .nan }
        return sxy / sqrt(sxx * syy)
    }

    public static func spearman(_ x: [Double], _ y: [Double]) -> Double { pearson(ranks(x), ranks(y)) }

    /// Two-sided p-value for a correlation coefficient (t approximation).
    public static func correlationPValue(r: Double, n: Int) -> Double {
        guard n > 2, r.isFinite else { return 1 }
        if abs(r) >= 1 { return 0 }
        let t = r * sqrt(Double(n - 2) / (1 - r * r))
        return 2 * (1 - studentTCDF(abs(t), df: Double(n - 2)))
    }

    public struct WelchResult: Sendable { public var t: Double; public var df: Double; public var p: Double }

    /// Welch's unequal-variance t-test (two-sided).
    public static func welch(_ a: [Double], _ b: [Double]) -> WelchResult {
        guard a.count > 1, b.count > 1 else { return WelchResult(t: 0, df: 0, p: 1) }
        let va = variance(a) / Double(a.count), vb = variance(b) / Double(b.count)
        let se = sqrt(va + vb)
        guard se > 0 else { return WelchResult(t: 0, df: 0, p: mean(a) == mean(b) ? 1 : 0) }
        let t = (mean(a) - mean(b)) / se
        let df = (va + vb) * (va + vb) / (va * va / Double(a.count - 1) + vb * vb / Double(b.count - 1))
        return WelchResult(t: t, df: df, p: 2 * (1 - studentTCDF(abs(t), df: df)))
    }

    /// Student's t CDF via the regularized incomplete beta function.
    public static func studentTCDF(_ t: Double, df: Double) -> Double {
        let x = df / (df + t * t)
        let ib = incompleteBeta(x, a: df / 2, b: 0.5)
        return t >= 0 ? 1 - 0.5 * ib : 0.5 * ib
    }

    /// Regularized incomplete beta I_x(a, b) (Numerical Recipes, continued fraction).
    public static func incompleteBeta(_ x: Double, a: Double, b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lbeta = lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x)
        let front = exp(lbeta)
        if x < (a + 1) / (a + b + 2) { return front * betaCF(x, a, b) / a }
        return 1 - front * betaCF(1 - x, b, a) / b
    }

    static func betaCF(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let maxIter = 200, eps = 3e-14, fpmin = 1e-300
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0, d = 1 - qab * x / qap
        if abs(d) < fpmin { d = fpmin }
        d = 1 / d
        var h = d
        for m in 1...maxIter {
            let m2 = Double(2 * m), md = Double(m)
            var aa = md * (b - md) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d; if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c; if abs(c) < fpmin { c = fpmin }
            d = 1 / d; h *= d * c
            aa = -(a + md) * (qab + md) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d; if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c; if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            let del = d * c
            h *= del
            if abs(del - 1) < eps { break }
        }
        return h
    }

    /// Benjamini–Hochberg: returns indices of p-values significant at FDR q.
    public static func benjaminiHochberg(_ p: [Double], q: Double) -> Set<Int> {
        let order = p.indices.sorted { p[$0] < p[$1] }
        let m = Double(p.count)
        var k = -1
        for (rank, i) in order.enumerated() where p[i] <= Double(rank + 1) / m * q { k = rank }
        guard k >= 0 else { return [] }
        return Set(order[0...k])
    }
}
