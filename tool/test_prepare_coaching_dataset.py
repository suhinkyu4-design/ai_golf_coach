import copy
import unittest
from prepare_coaching_dataset import validate, partition


def fixture(n):
    # Synthetic records are ONLY unit-test fixtures, never deliverable training data.
    return {
        'schema_version': 'golf_coaching_dataset_1.0', 'source': 'app_measured_unreviewed',
        'record_id': f'r{n}', 'golfer_id': f'g{n}', 'session_id': f's{n}', 'training_consent': True,
        'input': {'view': 'rear', 'handedness': 'right', 'club': '7i', 'events_user_confirmed': True,
                  'pose_measurements': {'measurement_version': 'pose_metrics_1.0',
                      'metrics': [{'id': f'{kind}_projected_at_{phase}', 'kind': kind, 'phase': phase,
                                   'value': 90, 'status': 'estimated', 'unit': 'deg', 'min_joint_likelihood': 0.9}
                                  for phase in ['address', 'top', 'impact', 'finish']
                                  for kind in ['lead_elbow', 'trail_elbow', 'lead_knee', 'trail_knee', 'torso_tilt']]}},
        'review': {'status': 'approved', 'reviewer_id': 'test', 'reviewed_at': '2026-09-16',
                   'decision': 'observation_only', 'evidence_metric_ids': ['lead_elbow_projected_at_address'], 'observation': 'Test only'},
    }


class DatasetTests(unittest.TestCase):
    def test_review_gate(self):
        for field, value in [('training_consent', False), ('golfer_id', None)]:
            row = fixture(0); row[field] = value
            with self.assertRaises(ValueError): validate(row)
        row = fixture(0); row['review']['status'] = 'pending'
        with self.assertRaises(ValueError): validate(row)

    def test_evidence_gate(self):
        row = fixture(0); row['review']['evidence_metric_ids'] = ['invented']
        with self.assertRaises(ValueError): validate(row)
        row = fixture(0); row['input']['pose_measurements']['metrics'][0].update(value=None, status='unavailable', reason='missing')
        with self.assertRaises(ValueError): validate(row)

    def test_cannot_assess(self):
        row = fixture(0)
        row['review'].update(decision='cannot_assess', evidence_metric_ids=[], cannot_assess_reason='Occluded')
        validate(row)
        row['review']['correction'] = 'Unsupported advice'
        with self.assertRaises(ValueError): validate(row)

    def test_split_no_leakage(self):
        rows = [fixture(i) for i in range(12)]
        extra = copy.deepcopy(rows[0]); extra.update(record_id='extra', golfer_id='other')
        rows.append(extra)
        splits = partition(rows)
        names = list(splits)
        for i, name in enumerate(names):
            for other in names[i+1:]:
                for field in ['golfer_id', 'session_id']:
                    self.assertFalse({r[field] for r in splits[name]} & {r[field] for r in splits[other]})
        self.assertEqual(sum(map(len, splits.values())), len(rows))


if __name__ == '__main__': unittest.main()
