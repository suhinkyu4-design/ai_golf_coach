# Casting observation stage — 2026-09-19

## Scope
Measure the projected angle between the lead forearm (wrist to elbow) and a short, visible shaft ray (grip toward shaft). No club head is required. This is not an anatomical wrist-cocking angle. Hand/finger positions, elbow straightening or hand-versus-hip translation are not substituted for the shaft.

## Image evidence
Near-grip search preserves image height up to 1280 pixels; scans 0.10–0.85 projected torso lengths from the wrist midpoint and requires at least 0.35 torso lengths of supported line. Existing moving-line, ambiguity, forearm-direction, image-duplicate and temporal continuity gates remain. Candidates carry false identity_verified/head_detected; they do not enter the verified club-head channel. The original full-ray trace remains separate.

## Temporal measurement
- Select the lead side from handedness; use upright image coordinates.
- Find the first observed downward wrist-midpoint crossing of the current frame hip midpoint between top and impact. Require a preceding observation within 100 ms. Never substitute 50% of downswing duration.
- Reject short/foreshortened forearms, disconnected grip geometry, missing or uncertain landmarks, unsupported shaft candidates, mismatched dimensions/timestamps and duplicate frames.
- Median-three projected angle observations with neighbor gaps <=100 ms. Compare observations near top and actual crossing only when a continuous sequence exists. Preserve signed opening change.
- No 90/100/120-degree diagnostic thresholds are used. No normal/casting grade is emitted. Rear-view angle visibility and candidate identity must be validated first.

## UI
Normal result cards remain unchanged. Settings → measurement details → Casting angle verification offers forearm and shaft overlays. Blue marks the lead forearm; green/orange marks supported/unconfirmed shaft candidates. A green line is not proof of club identity.

## Validation
Standalone synthetic checks: signed angle change, reflection invariance, correct lead side, low-confidence rejection, missing real halfway event, sequence gaps, short-shaft detection and static-line rejection. Existing tracker and nine-pattern checks retained. Real-phone results and screenshots are in workspace outputs/casting. Synthetic tests verify computation, not diagnostic accuracy.

## Real-phone evaluation

- Case 0: 108 samples, 40510 ms total pipeline; 9 projected angle observations; actual hand/hip crossing at 5322 ms. Result unavailable: halfway_angle_unavailable.
- Case 1: 99 samples, 37457 ms total pipeline; 6 projected angle observations; actual hand/hip crossing at 2984 ms. Result unavailable: halfway_angle_unavailable.

Visual overlay review of case 0 shows visible shaft alignment in selected top/early-down frames, but projected angles around 162–177 degrees. These must not be interpreted as anatomical wrist release or used with the proposed 120-degree casting cutoff. Both clips lack reliable shaft angle at the hand/hip crossing. Automatic casting diagnosis remains disabled.


## Tracker v3 refinement

- Near-grip rays search five fixed lateral origins (up to 8% of torso length, capped at 12 working-image pixels). One origin is held for the entire ray. Offset hypotheses cannot stitch unrelated pixels into a line.
- Retain up to four image-supported angular hypotheses separated by at least 18 degrees and within 0.12 score of the local best. This score is not calibrated probability.
- An ambiguous interior frame can select exactly one observed hypothesis matching two originally unambiguous neighbors within 16 degrees each, with neighbors differing by at most 30 degrees. Each neighbor gap must be at most 100 ms. No recursive propagation, missing-line synthesis or interpolation through occlusion. Final original continuity/geometry gates still apply.
- Preserve original angle/status and selection_method in diagnostics. Candidate identity remains unverified; automatic casting diagnosis stays disabled.
- Regression checks include displaced synthetic grip, resolving an opposite-direction distractor and rejection when no supported hypothesis matches the neighboring direction. Synthetic geometry tests and original feature tests pass.

Final v3 keeps an unambiguous centered ray in preference to the expanded offset search. This prevents broader search from replacing previously usable observations with background ambiguity.
- Final device case 0: 10 angle observations, 41317 ms pipeline. Diagnostic status remains unavailable.
- Final device case 1: 8 angle observations, 40246 ms pipeline. Diagnostic status remains unavailable.
- Case 1 at 2984 ms: image-supported 242-degree shaft hypothesis recovered from an opposite-direction distractor using neighboring anchors. Overlay inspected locally. Its raw projected forearm/shaft angle is approximately 12.8 degrees, not a validated wrist-cocking measurement.
- At 2951 ms the detected lead elbow and wrist are only about 10.6 pixels apart; the foreshortening/short-vector gate rejects them. The isolated recovered angle cannot support a continuous comparison.
- Final UI/report differentiates a missing angle from an observed angle without a supporting sequence (`halfway_angle_sequence_unavailable`). Raw observation is retained; no normal/error verdict is emitted. An isolated-angle regression test passes.


## Arm crop re-detection

- Only weak/short lead forearms during top-to-impact trigger a second accurate ML Kit observation. Maximum 12 attempts. Full-body context is retained in the crop and resized to height 1280; no generative reconstruction or filled-in joints.
- Crop landmarks are mapped back using independent x/y resize factors and crop offsets. Temporary crops are removed after inference.
- Confidence, projected length, wrist/shoulder proximity and two original neighboring arm observations within 100 ms gate acceptance. Neighbor positions are used only for consistency checks; they are never substituted as the measured coordinates. No recursive adoption of refined anchors.
- Original landmarks remain unchanged for existing rules and shaft detection. Accepted elbow/wrist coordinates are separate casting_landmarks; the optional review overlay uses the same coordinates as the angle calculation.
- Detailed crop/rejection evidence is exposed in the debug provider check. Detection and selection failures remain nonfatal to original measurements. Acceptance means passing heuristic consistency checks, not ground-truth joint verification.

### Crop experiment on actual phone
- Case 0: 8 retries, 0 accepted, 10 angle observations; 44618 ms total. No improvement to usable continuous casting evidence.
- Case 1: 4 retries, 0 accepted, 8 angle observations; 41659 ms total. No improvement to usable continuous casting evidence.
- At case 1 / 2951 ms, lead elbow–wrist distance shrank from about 10.6 px to 5.1 px after cropping; the image does not yield a reliable visible forearm direction. At 2919 ms the refined wrist shifted roughly 39 px, so adoption was rejected. Overlay comparison is in workspace outputs/casting/arm_refinement/forearm_comparison_2951.jpg.
- Rejection diagnostics now distinguish short forearm, excessive wrist/shoulder movement, low confidence and disagreement with original neighboring observations. No threshold was relaxed to force an answer.
- Automatic casting diagnosis remains disabled. This experiment tests a crop-based recovery option; it does not demonstrate improved detection accuracy on these clips.


## Visible downswing segments (2026-09-19)

Version 2 also reports visible_segments independently of top/halfway comparison. Only observations within top..impact are included. A rejected unique image or a gap over 100 ms splits a run; repeated native-image candidates do not increase its length. Each accepted run needs at least six distinct observations and 60 ms duration. Endpoint angles are medians of separate three-observation windows. The longest duration is selected; all accepted runs remain in the report. These are engineering coverage gates, not validated casting diagnostic thresholds. No missing angle is interpolated.

A segment can exist when halfway is not observed. The existing phase-specific status and reason remain unchanged; segment_status is independent. The UI shows the segment only in optional measurement details, with a partial-coverage caveat. diagnosis stays null and release_enabled stays false.

Synthetic verification covers missing halfway, rejected intervening frames, duplicate images and preserved no-diagnosis behavior.

Actual installed-phone provider checks:

Case 1: 8 angles; longest run 5; selected null; phase result halfway_angle_sequence_unavailable.

Case 0: 10 angles; longest run 8; selected {"start_t_ms": 4875, "end_t_ms": 5090, "frame_count": 8, "duration_ms": 215, "start_angle_deg": 176.03769483001133, "end_angle_deg": 175.61105186014356, "change_deg": -0.42664296986777117, "start_fraction": 0.0, "end_fraction": 0.446985446985447, "includes_halfway": false, "angle_basis": "median_of_three_distinct_observations_at_each_end"}; phase result halfway_angle_unavailable.

Case 0 covers only the first 44.7% of the downswing. This does not establish lag or casting. Existing diagnostic rules and no-diagnosis gates are unchanged. Build/install and both actual-provider checks passed.
