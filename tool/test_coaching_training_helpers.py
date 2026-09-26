import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from coaching_training_helpers import model_input, audit_answer, encode_completion, CompletionCollator
from prepare_coaching_dataset import prepare, sft_record
from test_prepare_coaching_dataset import fixture
from build_colab_notebook import build


class FakeTokenizer:
    eos_token_id = 999999
    def apply_chat_template(self, messages, **kwargs):
        assert kwargs['enable_thinking'] is False
        return '|prompt|'
    def encode(self, text, **kwargs):
        return list(text.encode('utf-8'))


class TrainingHelpersTests(unittest.TestCase):
    def setUp(self):
        self.record = fixture(1)
        self.inp = model_input(self.record['input'])
        self.answer = json.loads(sft_record(self.record)['messages'][2]['content'])

    def test_compact_input_keeps_uncertainty(self):
        self.assertTrue(self.inp['angles_are_2d_projections'])
        self.assertFalse(self.inp['video_pts_synchronized'])
        self.assertEqual(len(self.inp['measurements']), 20)
        self.assertNotIn('review', self.inp)

    def test_valid_observation(self):
        result = audit_answer(json.dumps(self.answer), self.inp, self.answer)
        self.assertTrue(result['contract_valid'])
        self.assertTrue(result['decision_match'])

    def test_bad_json_and_types(self):
        for raw in ['not json', '[]', '{"value": NaN}']:
            self.assertFalse(audit_answer(raw, self.inp)['contract_valid'])
        self.answer['evidence_metric_ids'] = 'wrong'
        self.assertFalse(audit_answer(json.dumps(self.answer), self.inp)['contract_valid'])

    def test_unknown_and_missing_evidence(self):
        self.answer['evidence_metric_ids'] = ['unknown']
        self.assertIn('unknown_evidence', audit_answer(json.dumps(self.answer), self.inp)['issues'])
        self.answer['evidence_metric_ids'] = ['lead_elbow_projected_at_address']
        self.inp['measurements']['lead_elbow_projected_at_address']['status'] = 'unavailable'
        self.assertIn('unavailable_evidence', audit_answer(json.dumps(self.answer), self.inp)['issues'])

    def test_cannot_assess_and_degree_flags(self):
        self.answer.update(decision='cannot_assess', evidence_metric_ids=[], cannot_assess_reason='관절 가림')
        self.assertTrue(audit_answer(json.dumps(self.answer), self.inp)['contract_valid'])
        self.answer['correction'] = '무조건 펴세요'
        self.assertIn('advice_despite_abstention', audit_answer(json.dumps(self.answer), self.inp)['issues'])
        self.answer['correction'] = None
        self.answer['observation'] = '각도 176도'
        self.assertEqual(audit_answer(json.dumps(self.answer), self.inp)['degree_claims_to_review'], ['176'])

    def test_completion_mask_and_overlength(self):
        example = sft_record(self.record)
        encoded = encode_completion(FakeTokenizer(), example)
        self.assertEqual(encoded['labels'][:8], [-100]*8)
        self.assertEqual(encoded['labels'][8:-1], list(example['messages'][2]['content'].encode('utf-8')))
        self.assertEqual(encoded['labels'][-1], FakeTokenizer.eos_token_id)
        self.assertEqual(len(encoded['labels']), len(encoded['input_ids']))
        with self.assertRaises(ValueError): encode_completion(FakeTokenizer(), example, max_length=10)

    def test_padding_is_not_trained(self):
        class FakeTorch:
            long = 'long'
            @staticmethod
            def tensor(value, **kwargs): return value
        examples = [{'input_ids': [1, 2], 'attention_mask': [1, 1], 'labels': [-100, 2]},
                    {'input_ids': [3], 'attention_mask': [1], 'labels': [3]}]
        with patch.dict('sys.modules', {'torch': FakeTorch}):
            batch = CompletionCollator(0)(examples)
        self.assertEqual(batch['labels'][1], [3, -100])
        self.assertEqual(batch['attention_mask'][1], [1, 0])

    def test_complete_pipeline_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'reviewed'; source.mkdir()
            for i in range(5):
                row = fixture(i)
                row['input']['pose_measurements']['metrics'][0]['value'] = 90+i
                (source / f'{i}.json').write_text(json.dumps(row), encoding='utf-8')
            dest = Path(temp) / 'prepared'
            manifest = prepare(source, dest)
            self.assertEqual(sum(manifest['counts'].values()), 5)
            self.assertEqual(manifest['model_input_version'], 'golf_coaching_input_1.0')
            with self.assertRaises(ValueError): prepare(source, dest)
            self.assertEqual(len((dest / 'train.jsonl').read_text(encoding='utf-8').splitlines()), 3)

    def test_pending_export_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'pending'; source.mkdir()
            row = fixture(1); row['review']['status'] = 'pending'
            (source / 'one.json').write_text(json.dumps(row))
            with self.assertRaisesRegex(ValueError, '승인'): prepare(source, Path(temp) / 'prepared')

    def test_notebook_code_and_embedded_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            nb = build(Path(temp) / 'test.ipynb')
            for i, cell in enumerate(nb['cells']):
                if cell['cell_type'] == 'code':
                    compile(cell['source'], f'cell_{i}', 'exec')
                    self.assertIsNone(cell['execution_count'])
                    self.assertEqual(cell['outputs'], [])
            embedded = nb['cells'][3]['source']
            namespace = {'ROOT': Path(temp)}
            # Only execute the helper-writing bootstrap; skip sys.path/import lines.
            for line in embedded.splitlines()[:2]: exec(line, namespace)
            for name in ['prepare_coaching_dataset.py', 'coaching_training_helpers.py']:
                self.assertEqual((Path(temp)/name).read_text(encoding='utf-8'), (Path(__file__).parent/name).read_text(encoding='utf-8'))


if __name__ == '__main__': unittest.main()
