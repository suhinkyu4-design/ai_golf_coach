# Multiple-swing selection (2026-09-22)

Pose schema 3.5, selection cache version 4, impact diagnostics v4.

Previously, `scanWindow` returned the first wrist rise/return. Practice swings
could therefore become the selected swing even without ball evidence.

The gallery pipeline now enumerates candidate cycles and extracts each impact
window densely. A new cycle must return near the previous address hand height
for at least 200ms; the brief impact-to-finish motion must not re-arm a cycle.
Each candidate records its own phase window and visual evidence. The UI uses
the selected window, rather than independently choosing the first reversal.

Ball search covers a wider lateral ground region, compares up to 12 compact
bright components and checks disappearance with a nearby moving club trace.
Both luminance thresholds are considered, deduplicating the same component;
finding a bright background component must not prevent the higher-threshold pass.
Temporary occlusion followed by reappearance is rejected; absence must persist
at least 100ms in the available window. Images are decoded once per candidate
window at no more than 640px height to bound multi-track memory/cost. These are
unverified image candidates, not an object detector or confirmed clubhead.
Club traces are computed only around a sustained disappearance, avoiding repeated
full club scans for stationary candidates.

Exactly one visually supported hit across cycles is automatically selected.
With multiple possible hits, or multiple cycles without a unique visual hit,
automatic selection stops and the existing settings entry allows a range choice.
For a single detected cycle only, the existing pose-based timing fallback remains.
Thus a lone practice swing is not guaranteed to be identified as practice.
Neither confidence scores nor the last/first position alone break ambiguity.

Progress text includes candidate index/count. Old automatic review caches are
invalidated; user-reviewed phase selections remain usable.

Validation:
- Synthetic image + pose tests: practice followed by hit, two practices followed
  by hit, no hit, two possible hits, temporary occlusion, brighter stationary
  distractor, sparse/missing input, finish rejection and address reset.
- Saved real 30-second video: two candidate cycles, top 8451/27354ms. PC image
  replay selects ball/club events near 9047/27853ms independently and withholds
  a single automatic selection. A spurious followthrough cycle was eliminated.
- Connected SM-F741N: 20-second gallery video yielded `unique_visual_hit` with
  one candidate, then completed automatic movement analysis and result UI.
- Casting and over-the-top rule checks pass. Static analyzer reports no warnings
  or errors in the changed files. APK compiled and installed successfully.

Evidence in task workspace: `outputs/multiple_swings/v4/real_result.json`,
`phone20.json`, `phone20_result.png`. Synthetic checks do not establish a real
practice-vs-hit accuracy rate; additional labelled recordings remain useful.

Final phone check: the same 30-second gallery video produced two visually
supported hits (9029ms and 27863ms, tops 8520ms and 27354ms). It returned
`ambiguous_multiple_swings / multiple_visual_hits` and displayed the multiple-hit
range-choice message instead of analyzing the first swing. The settings gear
successfully opened phase/range editing. Evidence: `phone30_final.json` and
`phone30_choice.png` in the same task evidence directory. Native closest-frame
timestamps differ slightly from desktop OpenCV replay; neither is decoded PTS.

The final packaged APK is 146416707 bytes. The immediately preceding phone-tested
build differs only by removal of an always-null local used to initialize trace
fields; it has identical selection behavior. Final analyzer warnings/errors: 0.
