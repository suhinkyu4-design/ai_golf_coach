"""Shared model-input, answer auditing and completion-only tokenization helpers.

No GPU/library dependencies at import time; the notebook imports Torch lazily.
Automated checks do not certify coaching correctness.
"""
import json
import re

MODEL_INPUT_VERSION = 'golf_coaching_input_1.0'
ANSWER_KEYS = {'decision', 'evidence_metric_ids', 'observation', 'correction',
               'drill_id', 'drill_instructions', 'cannot_assess_reason'}


def model_input(app_input):
    """Keep evidence and uncertainties, omit repeated joint names/display metadata."""
    report = app_input['pose_measurements']
    return {
        'input_version': MODEL_INPUT_VERSION,
        'view': app_input['view'], 'handedness': app_input['handedness'],
        'club': app_input['club'], 'events_ms': app_input.get('events_ms', {}),
        'events_user_confirmed': app_input['events_user_confirmed'],
        'measurement_version': report['measurement_version'],
        'coordinate_space': 'upright_image_pixels',
        'angle_unit': 'deg', 'angles_are_2d_projections': True,
        'torso_tilt_convention': 'screen_up_zero_screen_right_positive',
        'timestamp_basis': report.get('timestamp_basis', 'unknown'),
        'video_pts_synchronized': report.get('video_pts_synchronized', False),
        'joint_likelihood_is_not_angle_accuracy': True,
        'measurements': {
            row['id']: {
                'value': row['value'], 'status': row['status'],
                'reason': row.get('reason'),
                'min_joint_likelihood': row.get('min_joint_likelihood'),
                'sample_t_ms': row.get('sample_t_ms'),
            } for row in report['metrics']
        },
    }


def _text(value):
    return isinstance(value, str) and bool(value.strip())


def audit_answer(raw, inp, reference=None):
    result = {'json_valid': False, 'contract_valid': False, 'decision_match': False,
              'evidence_exact_match': False, 'issues': [], 'degree_claims_to_review': []}
    try:
        answer = json.loads(raw, parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
    except (ValueError, TypeError):
        result['issues'] = ['invalid_json']
        return result
    result['json_valid'] = True
    if not isinstance(answer, dict) or set(answer) != ANSWER_KEYS:
        result['issues'] = ['wrong_output_keys']
        return result
    decision = answer['decision']
    evidence = answer['evidence_metric_ids']
    measurements = inp['measurements']
    if decision not in ['observation_only', 'correction', 'cannot_assess']:
        result['issues'].append('invalid_decision')
    valid_ids = isinstance(evidence, list) and all(isinstance(k, str) for k in evidence)
    if not valid_ids:
        result['issues'].append('invalid_evidence_list')
        evidence = []
    elif len(set(evidence)) != len(evidence):
        result['issues'].append('duplicate_evidence')
    if any(k not in measurements for k in evidence):
        result['issues'].append('unknown_evidence')
    for key in ANSWER_KEYS - {'decision', 'evidence_metric_ids'}:
        if answer[key] is not None and not _text(answer[key]):
            result['issues'].append('invalid_text:' + key)
    if decision == 'cannot_assess':
        if not _text(answer['cannot_assess_reason']):
            result['issues'].append('missing_abstention_reason')
        if any(answer[k] is not None for k in ['correction', 'drill_id', 'drill_instructions']):
            result['issues'].append('advice_despite_abstention')
    elif decision in ['correction', 'observation_only']:
        if not inp['events_user_confirmed'] or inp['view'] == 'unknown':
            result['issues'].append('unconfirmed_input')
        if not evidence or any(measurements.get(k, {}).get('status') != 'estimated' for k in evidence):
            result['issues'].append('unavailable_evidence')
        if not _text(answer['observation']):
            result['issues'].append('missing_observation')
        if answer['cannot_assess_reason'] is not None:
            result['issues'].append('conflicting_abstention')
        if decision == 'correction':
            if not all(_text(answer[k]) for k in ['correction', 'drill_id', 'drill_instructions']):
                result['issues'].append('incomplete_drill')
        elif any(answer[k] is not None for k in ['correction', 'drill_id', 'drill_instructions']):
            result['issues'].append('advice_in_observation_only')
    # A review flag, not a correctness score: e.g. a drill may legitimately name a new angle.
    values = [r['value'] for r in measurements.values() if isinstance(r.get('value'), (int, float))]
    prose = ' '.join(answer[k] for k in ANSWER_KEYS - {'decision', 'evidence_metric_ids'} if isinstance(answer[k], str))
    for degree in re.findall(r'([+-]?\d+(?:\.\d+)?)\s*(?:°|도)', prose):
        if not any(abs(float(degree) - v) <= 0.51 for v in values):
            result['degree_claims_to_review'].append(degree)
    result['contract_valid'] = not result['issues']
    if reference:
        result['decision_match'] = decision == reference['decision']
        result['evidence_exact_match'] = valid_ids and set(evidence) == set(reference['evidence_metric_ids'])
    return result


def encode_completion(tokenizer, record, max_length=4096):
    messages = record['messages']
    if [m['role'] for m in messages] != ['system', 'user', 'assistant']:
        raise ValueError('Expected system/user/assistant messages')
    # Use the identical non-thinking prefix for training and inference.
    prefix = tokenizer.apply_chat_template(messages[:2], tokenize=False,
                                          add_generation_prompt=True, enable_thinking=False)
    prompt_ids = tokenizer.encode(prefix, add_special_tokens=False)
    answer_ids = tokenizer.encode(messages[2]['content'], add_special_tokens=False)
    if not answer_ids or tokenizer.eos_token_id is None:
        raise ValueError('Missing answer or EOS token')
    answer_ids += [tokenizer.eos_token_id]
    ids = prompt_ids + answer_ids
    if len(ids) > max_length:
        raise ValueError(f'Example has {len(ids)} tokens > {max_length}; do not truncate evidence or answers')
    return {'input_ids': ids, 'attention_mask': [1] * len(ids),
            'labels': [-100] * len(prompt_ids) + answer_ids}


class CompletionCollator:
    def __init__(self, pad_token_id):
        self.pad_token_id = pad_token_id

    def __call__(self, examples):
        import torch
        length = max(len(x['input_ids']) for x in examples)
        result = {key: [] for key in ['input_ids', 'attention_mask', 'labels']}
        for example in examples:
            n = length - len(example['input_ids'])
            for key, padding in [('input_ids', self.pad_token_id), ('attention_mask', 0), ('labels', -100)]:
                result[key].append(example[key] + [padding] * n)
        return {key: torch.tensor(value, dtype=torch.long) for key, value in result.items()}


def evaluate_model(model, tokenizer, records, destination):
    import time
    import torch
    from pathlib import Path
    model.eval()
    predictions = []
    for i, record in enumerate(records):
        prompt = tokenizer.apply_chat_template(record['messages'][:2], tokenize=False,
                                              add_generation_prompt=True, enable_thinking=False)
        encoded = tokenizer(prompt, return_tensors='pt', add_special_tokens=False).to(model.device)
        torch.cuda.synchronize()
        started = time.perf_counter()
        with torch.inference_mode():
            generated = model.generate(**encoded, max_new_tokens=512, do_sample=False,
                                       temperature=None, top_p=None, top_k=None,
                                       pad_token_id=tokenizer.pad_token_id,
                                       eos_token_id=tokenizer.eos_token_id, use_cache=True)
        torch.cuda.synchronize()
        new_ids = generated[0, encoded['input_ids'].shape[1]:]
        raw = tokenizer.decode(new_ids, skip_special_tokens=True)
        inp = json.loads(record['messages'][1]['content'])
        reference = json.loads(record['messages'][2]['content'])
        predictions.append({'index': i, 'input': inp, 'reference': reference, 'prediction': raw,
                            'elapsed_seconds': round(time.perf_counter() - started, 3),
                            'output_tokens': len(new_ids),
                            'ended_with_eos': new_ids[-1].item() == tokenizer.eos_token_id,
                            'audit': audit_answer(raw, inp, reference),
                            'instructor_review': None})
    Path(destination).write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in predictions), encoding='utf-8')
    n = len(predictions)
    if not n:
        raise ValueError('Empty evaluation set')
    summary = {key + '_rate': sum(p['audit'][key] for p in predictions) / n
               for key in ['json_valid', 'contract_valid', 'decision_match', 'evidence_exact_match']}
    abstentions = [p for p in predictions if p['reference']['decision'] == 'cannot_assess']
    summary.update(count=n, cannot_assess_count=len(abstentions),
                   cannot_assess_recall=(sum(p['audit']['decision_match'] for p in abstentions) / len(abstentions)) if abstentions else None,
                   degree_claims_flagged=sum(bool(p['audit']['degree_claims_to_review']) for p in predictions),
                   truncated_outputs=sum(not p['ended_with_eos'] for p in predictions),
                   mean_seconds=sum(p['elapsed_seconds'] for p in predictions)/n,
                   coaching_correctness='requires_instructor_review', device_speed='not_measured_on_phone')
    return summary
