import CoreLocation
import MapKit

// Vincenty formula on the WGS84 ellipsoid.
// Accurate to ~0.06 mm for any two points on Earth.
// Reference: T. Vincenty, "Direct and Inverse Solutions of Geodesics on the
// Ellipsoid with Application of Nested Equations", Survey Review, 1975.
func vincentyDistance(
    _ c1: CLLocationCoordinate2D,
    _ c2: CLLocationCoordinate2D
) -> CLLocationDistance {

    // WGS84 constants
    let a = 6_378_137.0             // semi-major axis (metres)
    let f = 1.0 / 298.257_223_563   // flattening
    let b = a * (1.0 - f)           // semi-minor axis

    let toRad = Double.pi / 180.0
    let lat1 = c1.latitude  * toRad
    let lon1 = c1.longitude * toRad
    let lat2 = c2.latitude  * toRad
    let lon2 = c2.longitude * toRad

    let L = lon2 - lon1

    let tanU1 = (1.0 - f) * tan(lat1)
    let cosU1 = 1.0 / sqrt(1.0 + tanU1 * tanU1)
    let sinU1 = tanU1 * cosU1

    let tanU2 = (1.0 - f) * tan(lat2)
    let cosU2 = 1.0 / sqrt(1.0 + tanU2 * tanU2)
    let sinU2 = tanU2 * cosU2

    var lambda = L
    var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0
    var sinAlpha = 0.0, cos2Alpha = 0.0, cos2SigmaM = 0.0

    for _ in 0 ..< 200 {
        let sinLam = sin(lambda), cosLam = cos(lambda)
        let p = cosU2 * sinLam
        let q = cosU1 * sinU2 - sinU1 * cosU2 * cosLam
        sinSigma  = sqrt(p * p + q * q)
        if sinSigma == 0 { return 0 }           // coincident points
        cosSigma  = sinU1 * sinU2 + cosU1 * cosU2 * cosLam
        sigma     = atan2(sinSigma, cosSigma)
        sinAlpha  = cosU1 * cosU2 * sinLam / sinSigma
        cos2Alpha = 1.0 - sinAlpha * sinAlpha
        cos2SigmaM = cos2Alpha == 0 ? 0.0
                   : cosSigma - 2.0 * sinU1 * sinU2 / cos2Alpha

        let C = f / 16.0 * cos2Alpha * (4.0 + f * (4.0 - 3.0 * cos2Alpha))
        let lambdaNew = L + (1.0 - C) * f * sinAlpha * (
            sigma + C * sinSigma * (
                cos2SigmaM + C * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)
            )
        )
        if abs(lambdaNew - lambda) < 1e-12 { lambda = lambdaNew; break }
        lambda = lambdaNew
    }

    let u2   = cos2Alpha * (a * a - b * b) / (b * b)
    let bigA = 1.0 + u2 / 16384.0 * (4096.0 + u2 * (-768.0 + u2 * (320.0 - 175.0 * u2)))
    let bigB = u2 / 1024.0 * (256.0 + u2 * (-128.0 + u2 * (74.0 - 47.0 * u2)))
    let dS   = bigB * sinSigma * (
        cos2SigmaM + bigB / 4.0 * (
            cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
            bigB / 6.0 * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma)
                                  * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)
        )
    )
    return b * bigA * (sigma - dS)
}

// Computes N evenly-spaced points on the geodesic circle using the Vincenty
// direct formula on the WGS84 ellipsoid — accurate to ~0.06 mm at any distance.
func geodesicCircleCoordinates(center: CLLocationCoordinate2D,
                                radius: CLLocationDistance,
                                steps: Int = 720) -> [CLLocationCoordinate2D] {
    let a  = 6_378_137.0
    let f  = 1.0 / 298.257_223_563
    let b  = a * (1.0 - f)
    let s  = radius
    let lat1 = center.latitude  * .pi / 180
    let lon1 = center.longitude * .pi / 180

    return (0..<steps).compactMap { step in
        let alpha1 = 2 * .pi * Double(step) / Double(steps)

        let sinA1 = sin(alpha1), cosA1 = cos(alpha1)
        let tanU1 = (1 - f) * tan(lat1)
        let cosU1 = 1 / sqrt(1 + tanU1 * tanU1)
        let sinU1 = tanU1 * cosU1

        let sigma1 = atan2(tanU1, cosA1)
        let sinAlpha  = cosU1 * sinA1
        let cos2Alpha = 1 - sinAlpha * sinAlpha
        let u2 = cos2Alpha * (a * a - b * b) / (b * b)
        let bigA = 1 + u2 / 16384 * (4096 + u2 * (-768 + u2 * (320 - 175 * u2)))
        let bigB = u2 / 1024  * (256  + u2 * (-128 + u2 * (74  - 47  * u2)))

        var sigma = s / (b * bigA)
        var cos2SigmaM = 0.0, sinSigma = 0.0, cosSigma = 0.0

        for _ in 0..<200 {
            cos2SigmaM = cos(2 * sigma1 + sigma)
            sinSigma   = sin(sigma)
            cosSigma   = cos(sigma)
            let dSigma = bigB * sinSigma * (
                cos2SigmaM + bigB / 4 * (
                    cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                    bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma)
                                        * (-3 + 4 * cos2SigmaM * cos2SigmaM)
                )
            )
            let sigmaNew = s / (b * bigA) + dSigma
            if abs(sigmaNew - sigma) < 1e-12 { sigma = sigmaNew; break }
            sigma = sigmaNew
        }

        let tmp  = sinU1 * sinSigma - cosU1 * cosSigma * cosA1
        let lat2 = atan2(sinU1 * cosSigma + cosU1 * sinSigma * cosA1,
                         (1 - f) * sqrt(sinAlpha * sinAlpha + tmp * tmp))
        let lam  = atan2(sinSigma * sinA1, cosU1 * cosSigma - sinU1 * sinSigma * cosA1)
        let C    = f / 16 * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha))
        let L    = lam - (1 - C) * f * sinAlpha * (
            sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM))
        )

        return CLLocationCoordinate2D(latitude:  lat2 * 180 / .pi,
                                      longitude: (lon1 + L) * 180 / .pi)
    }
}
