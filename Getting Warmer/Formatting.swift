import Foundation

func formatDistance(_ meters: Double) -> String {
    guard meters >= 1000 else { return "\(Int(meters)) m" }
    let km = meters / 1000
    if km < 10  { return String(format: "%.2f km", km) }
    if km < 100 { return String(format: "%.1f km", km) }
    return String(format: "%.0f km", km)
}

func formatDuration(from start: Date, to end: Date) -> String {
    let s = Int(end.timeIntervalSince(start))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    return "\(m / 60)h \(m % 60)m"
}
