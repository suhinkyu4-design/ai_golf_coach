# Gallery video regression

Run `dart test/gallery_video_regression_check.dart` and `dart test/impact_diagnostics_check.dart`.

`test/fixtures/gallery_video_regression.json` intentionally contains no video, frames, faces, or source paths. It records only device-observed pose timing and expected outcomes:

- `1000005888`: a fast downswing whose coarse scan must yield a swing window.
- `1000005887`: 8 detected poses of 59 because the golfer leaves the frame; it must remain a quality failure, not a rotation or ML Kit defect.
