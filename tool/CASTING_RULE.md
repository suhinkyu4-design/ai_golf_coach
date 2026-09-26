# Conditional projected casting screening

Casting is early release during downswing. Concept source: https://www.mytpi.com/improve-my-game/swing-characteristics/casting . The source does not establish the numerical thresholds below; they are provisional app heuristics, not validated diagnostic standards.

Require an observed wrist crossing of current hip height before impact, three distinct frames near the top and three near the crossing, continuous intermediate frames, image-supported shafts, finite angles, and stable projected forearm lengths. Reject jumps above 35 degrees, gaps above 60ms, missing intermediate observations and duplicate images. Rear-view forearms must span at least 40% of torso length. Without a visibly set initial angle (at most 100 degrees), no normal result is emitted.

Use nonoverlapping three-frame medians. Halfway angle at least 120 degrees with opening of at least 20 degrees is suspected casting. Halfway angle at least 100 degrees or opening of at least 20 degrees is warning; otherwise within this app rule. Floating-point boundary tolerance is 1e-8. These are projected forearm/shaft angles, not anatomical wrist angles or measured clubhead positions.

Only classified evidence produces a result card. Analysis Details explains unavailable evidence. Existing observations remain debug information. Tests cover positive, maintained and marginal release, missing phase, foreshortening, unsupported shafts, interrupted sequences, duplicate images, angle jumps, NaN and observation-to-rule integration. Real positive-video accuracy remains unvalidated.

## Positive-only early-downswing screen (v2)

When a complete top-to-hip comparison is unavailable, three consecutive unique images may establish a suspected open-angle pattern, never a normal result. Each shaft must have image support (distal moving ridge or agreement between the full and near-grip searches), and each projected angle minus its assumed endpoint-error margin must be at least 120 degrees. Wrists must remain at least 0.1 torso length above the pelvis, descend in every frame, and descend at least 0.3 torso length overall. Require at least 50ms duration, gaps at most 60ms, no missing observation indices, and angle jumps at most 35 degrees. Reject unreliable forearm projection and excessive assumed angular margin. Cross-scale agreement is not independent verification of club identity.

The result reports the median early-downswing angle and explicitly leaves top angle, halfway angle and opening change null. The margin assumes endpoint error of 2% of torso length; it is an engineering guard, not a statistical confidence interval. A held top, static hands, a late release below hip height, a missing image or an unsupported shaft cannot qualify. This remains a provisional 2D screening rule, not proof of the release start or a clinical/biomechanical diagnosis.

## Device validation, 2026-09-21

APK 146409157 bytes was installed on SM-F741N. A real 30.046-second side/oblique video was analyzed through the installed app's native provider pipeline in 44746ms. It produced `rule_classified / casting`, displayed label `캐스팅 의심`, using 8813, 8846 and 8879ms. Median projected angle was 160.522 degrees. The observed shaft overlays were visually inspected against the footage. The test used stored phase timestamps (top 8451ms, impact candidate 8962ms); it does not establish fresh automatic phase selection or end-to-end gallery UI success for this clip.

Evidence is saved in the task workspace at `outputs/over_top/casting_native_side_v2.json` and `outputs/over_top/side_casting_angles.jpg`. This is an actual-video app-rule detection, not independently labelled ground truth or an accuracy benchmark. A subsequent native regression run on another video was interrupted by USB disconnection, so its result and the final user-visible screen remain unverified. Earlier-version checks retained an unavailable casting result and a within-rule over-the-top result on that clip; those do not substitute for the interrupted v2 regression.

Current casting rule, observation integration, club tracking and over-the-top rule checks all pass. Reported analyzer output contains no warnings/errors. Tests include partial evidence never yielding normal, held-top rejection, late release rejection, assumed-error margin, missing frames, duplicate images and unsupported shafts.

## Reconnected phone follow-up

The interrupted regression was completed on the same installed build: case 1 took 36251ms, retained `halfway_angle_sequence_unavailable` for casting and `within_rule` for over-the-top. Full result: task workspace `outputs/over_top/casting_native_case1_v2.json`. This verifies conservative handling of that clip, not a ground-truth false-positive rate.

The 30-second gallery video dated 2026-09-19 21:37 was then selected through the actual app photo picker. The normal automatic video/phase and movement analysis completed without manual phase changes. The result screen displayed `캐스팅 의심` and `초기 다운스윙 팔·샤프트 각도 · 160.5°`. Expanding Casting in Analysis Details showed the three-frame early-downswing explanation and explicitly withheld the top angle/release-start time. Screenshot: task workspace `outputs/over_top/casting_result_v2.png`. This completes the previously outstanding gallery-to-result UI check for this clip.
