"""Validate instructor-reviewed app exports and create leakage-resistant SFT splits.
Python 3.10+, standard library only. No external services are called.
"""
import argparse
import hashlib
import json
import math
import random
from datetime import datetime
from pathlib import Path
from coaching_training_helpers import model_input, MODEL_INPUT_VERSION

SYSTEM = ('골프 영상의 측정 기록과 지도자 검토 기준에 따라 답하세요. '
          '입력에 없는 수치나 실제 3D 회전, 체중 분포, 클럽 페이스를 추정하지 마세요. '
          '근거가 부족하면 cannot_assess로 답하세요. '
          'decision, evidence_metric_ids, observation, correction, drill_id, '
          'drill_instructions, cannot_assess_reason 키를 가진 JSON만 출력하세요.')
OUTPUT_KEYS = ['decision', 'evidence_metric_ids', 'observation', 'correction',
               'drill_id', 'drill_instructions', 'cannot_assess_reason']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def validate(record):
    require(record.get('schema_version') == 'golf_coaching_dataset_1.0', 'schema_version 불일치')
    require(record.get('source') == 'app_measured_unreviewed', '실제 앱 측정 자료만 허용')
    require(record.get('training_consent') is True, '학습 사용 동의 없음')
    for key in ['record_id', 'golfer_id', 'session_id']:
        require(nonempty(record.get(key)), f'{key} 필요')
    review = record.get('review', {})
    require(review.get('status') == 'approved', '지도자 승인 필요')
    require(nonempty(review.get('reviewer_id')) and nonempty(review.get('reviewed_at')), '검토자/검토일 필요')
    datetime.fromisoformat(review['reviewed_at'].replace('Z', '+00:00'))
    inp = record.get('input', {})
    require(inp.get('view') in ['faceOn', 'rear', 'targetLine', 'unknown'], '촬영 방향 오류')
    require(inp.get('handedness') in ['right', 'left'], '주사용 손 오류')
    require(nonempty(inp.get('club')), '클럽 필요')
    report = inp.get('pose_measurements', {})
    require(report.get('measurement_version') == 'pose_metrics_1.0', '측정 버전 오류')
    rows = report.get('metrics', [])
    require(isinstance(rows, list) and len(rows) == 20, '네 자세의 20개 측정 레코드 필요')
    ids = set()
    usable = set()
    expected = {f'{kind}_projected_at_{phase}' for phase in ['address', 'top', 'impact', 'finish']
                for kind in ['lead_elbow', 'trail_elbow', 'lead_knee', 'trail_knee', 'torso_tilt']}
    for row in rows:
        key = row.get('id')
        require(nonempty(key) and key in expected and key not in ids, '측정 ID 오류/중복')
        require(key == f"{row.get('kind')}_projected_at_{row.get('phase')}", '측정 ID와 자세/종류 불일치')
        ids.add(key)
        value = row.get('value')
        status = row.get('status')
        if status == 'unavailable':
            require(value is None and nonempty(row.get('reason')), '측정 불가 값은 null과 사유 필요')
        else:
            require(status == 'estimated' and type(value) in (int, float) and math.isfinite(value), '측정값 오류')
            require(row.get('unit') == 'deg', '각도 단위 오류')
            likelihood = row.get('min_joint_likelihood')
            require(type(likelihood) in (int, float) and math.isfinite(likelihood) and 0.7 <= likelihood <= 1, '유효 측정의 관절 신뢰도 오류')
            require(-180 <= value <= 180 if row.get('kind') == 'torso_tilt' else 0 <= value <= 180, '각도 범위 오류')
            usable.add(key)
    decision = review.get('decision')
    require(decision in ['observation_only', 'correction', 'cannot_assess'], '검토 decision 오류')
    evidence = review.get('evidence_metric_ids')
    require(isinstance(evidence, list) and all(isinstance(k, str) for k in evidence), '근거 ID 목록 필요')
    require(set(evidence).issubset(ids), '존재하지 않는 근거 ID')
    if decision == 'cannot_assess':
        require(nonempty(review.get('cannot_assess_reason')), '판단 불가 사유 필요')
        require(all(review.get(k) is None for k in ['correction', 'drill_id', 'drill_instructions']), '판단 불가 사례에 교정 처방 금지')
    else:
        require(inp.get('events_user_confirmed') is True and inp.get('view') != 'unknown', '자세 시각/촬영 방향 확인 필요')
        require(bool(evidence) and set(evidence).issubset(usable), '유효한 수치 근거 필요')
        require(nonempty(review.get('observation')), '관찰 내용 필요')
        require(review.get('cannot_assess_reason') is None, '관찰/교정 결정에 판단 불가 사유 혼재')
        if decision == 'correction':
            require(all(nonempty(review.get(k)) for k in ['correction', 'drill_id', 'drill_instructions']), '교정 내용/연습 ID/방법 필요')
        else:
            require(all(review.get(k) is None for k in ['correction', 'drill_id', 'drill_instructions']), '관찰 전용 사례에 교정 처방 금지')
    return record


def partition(records):
    # Connected components: sharing either golfer OR session keeps records together.
    parent = {}
    def root(key):
        parent.setdefault(key, key)
        if parent[key] != key:
            parent[key] = root(parent[key])
        return parent[key]
    for row in records:
        a, b = root('g:' + row['golfer_id']), root('s:' + row['session_id'])
        parent[a] = b
    groups = {}
    for row in records:
        groups.setdefault(root('g:' + row['golfer_id']), []).append(row)
    groups = list(groups.values())
    require(len(groups) >= 3, '사람·촬영 세션이 겹치지 않는 독립 그룹 최소 3개 필요')
    random.Random(42).shuffle(groups)
    holdout = max(1, round(len(groups) * 0.1))
    result = {'test': groups[:holdout], 'validation': groups[holdout:2*holdout], 'train': groups[2*holdout:]}
    return {k: [r for group in v for r in group] for k, v in result.items()}


def sft_record(record):
    return {'messages': [
        {'role': 'system', 'content': SYSTEM},
        {'role': 'user', 'content': json.dumps(model_input(record['input']), ensure_ascii=False, allow_nan=False, separators=(',', ':'))},
        {'role': 'assistant', 'content': json.dumps({k: record['review'].get(k) for k in OUTPUT_KEYS}, ensure_ascii=False)},
    ]}


def prepare(source, output):
    paths = sorted(Path(source).glob('*.json'))
    require(bool(paths), '검토 JSON 파일이 없습니다.')
    records, failures, seen_ids, seen_inputs = [], [], set(), set()
    for path in paths:
        try:
            row = validate(json.loads(path.read_text(encoding='utf-8-sig')))
            digest = hashlib.sha256(json.dumps(row['input'], sort_keys=True).encode()).hexdigest()
            require(row['record_id'] not in seen_ids and digest not in seen_inputs, '중복 레코드/입력')
            seen_ids.add(row['record_id']); seen_inputs.add(digest)
            records.append(row)
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            failures.append(f'{path.name}: {error}')
    require(not failures, '\n'.join(failures))  # Fail closed; never silently train drafts.
    splits = partition(records)
    dest = Path(output)
    require(not dest.exists() or not any(dest.iterdir()), '출력 폴더는 새 폴더 또는 빈 폴더여야 합니다.')
    dest.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        (dest / f'{name}.jsonl').write_text(''.join(json.dumps(sft_record(r), ensure_ascii=False) + '\n' for r in rows), encoding='utf-8')
    manifest = {'schema_version': 'golf_coaching_dataset_1.0', 'seed': 42,
                'model_input_version': MODEL_INPUT_VERSION,
                'split_strategy': 'connected_golfer_and_session',
                'counts': {k: len(v) for k, v in splits.items()},
                'record_ids': {k: [r['record_id'] for r in v] for k, v in splits.items()}}
    (dest / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('reviewed_json_folder')
    parser.add_argument('output_folder')
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.reviewed_json_folder, args.output_folder), ensure_ascii=False, indent=2))
    except ValueError as error:
        parser.exit(1, str(error) + '\n')
