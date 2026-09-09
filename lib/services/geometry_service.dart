import 'dart:math';

class Point2D {
  final double x;
  final double y;
  final double visibility;

  Point2D(this.x, this.y, {this.visibility = 1.0});
}

class GeometryService {
  /// Calculate 2D angle in degrees between three joints: A - B - C (B is vertex)
  /// Formula: acos( clamp( (u . v) / (|u| * |v|), -1.0, 1.0 ) )
  static double calculate2DAngle(Point2D a, Point2D b, Point2D c) {
    final double ux = a.x - b.x;
    final double uy = a.y - b.y;
    final double vx = c.x - b.x;
    final double vy = c.y - b.y;

    final double uMag = sqrt(ux * ux + uy * uy);
    final double vMag = sqrt(vx * vx + vy * vy);

    if (uMag == 0 || vMag == 0) return 0.0;

    final double dot = ux * vx + uy * vy;
    final double cosAngle = (dot / (uMag * vMag)).clamp(-1.0, 1.0);

    return acos(cosAngle) * (180.0 / pi);
  }

  /// Torso length for normalization: distance between shoulder center and hip center at Address
  static double calculateTorsoLength(
      Point2D leftShoulder, Point2D rightShoulder, Point2D leftHip, Point2D rightHip) {
    final double shoulderCenterX = (leftShoulder.x + rightShoulder.x) / 2;
    final double shoulderCenterY = (leftShoulder.y + rightShoulder.y) / 2;
    final double hipCenterX = (leftHip.x + rightHip.x) / 2;
    final double hipCenterY = (leftHip.y + rightHip.y) / 2;

    final double dx = shoulderCenterX - hipCenterX;
    final double dy = shoulderCenterY - hipCenterY;
    return sqrt(dx * dx + dy * dy);
  }

  /// Upper body tilt angle relative to vertical axis (0 deg = pure vertical)
  static double calculateSpineTilt(
      Point2D leftShoulder, Point2D rightShoulder, Point2D leftHip, Point2D rightHip) {
    final double shoulderCenterX = (leftShoulder.x + rightShoulder.x) / 2;
    final double shoulderCenterY = (leftShoulder.y + rightShoulder.y) / 2;
    final double hipCenterX = (leftHip.x + rightHip.x) / 2;
    final double hipCenterY = (leftHip.y + rightHip.y) / 2;

    final double dx = shoulderCenterX - hipCenterX;
    final double dy = shoulderCenterY - hipCenterY;

    // Angle with vertical (y-axis)
    final double angleRad = atan2(dx, -dy); // -dy because screen Y points down
    return angleRad * (180.0 / pi);
  }
}
