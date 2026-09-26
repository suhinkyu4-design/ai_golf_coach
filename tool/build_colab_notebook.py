"""Build a self-contained, unexecuted Colab notebook from versioned helpers."""
import json
from pathlib import Path
import textwrap

HERE = Path(__file__).resolve().parent


def build(destination):
    cells = []
    def md(text):
        cells.append({'cell_type': 'markdown', 'metadata': {}, 'source': textwrap.dedent(text).strip() + '\n'})
    def code(text):
        cells.append({'cell_type': 'code', 'metadata': {}, 'execution_count': None,
                      'outputs': [], 'source': textwrap.dedent(text).strip() + '\n'})

    md('''
    # 골프 교정 SLM — 데이터 검증부터 QLoRA까지

    **이전 지도자 정답 기반 실험입니다. 현재 앱의 필수 절차가 아닙니다. 지도자 없이 진행하는 현재 방식은 golf_evidence_inference.ipynb를 사용하세요.**

    **준비된 학습 노트북이며 GPU 학습 실행을 검증한 결과물은 아닙니다. 학습된 모델은 포함되어 있지 않습니다.**

    순서: 검토 JSON 업로드 → 형식/근거 검증 → 사람·세션 분리 → 기준 모델 평가 → QLoRA → 동일 조건 비교 → 모델 병합/선택적 GGUF 변환.

    먼저 앱 측정값을 영상과 대조하고 지도자가 교정 정답을 작성하세요. `pending` 예시는 학습을 중단시키는 것이 정상입니다.
    가짜 검토자를 넣거나 정답을 임의로 승인해 통과시키지 마세요.

    Colab의 **런타임 → 런타임 유형 변경 → GPU**를 선택하세요. 데이터 검증까지는 GPU가 없어도 됩니다.
    업로드하는 JSON은 Google Colab 환경으로 전송됩니다. 원본 영상 업로드는 필요 없습니다.
    자료와 결과는 런타임 종료 시 없어질 수 있으므로 결과 ZIP을 다운로드하세요.
    이 노트북은 Hugging Face Hub에 자료나 모델을 게시하지 않습니다.
    ''')
    code('''
    import os, sys, json, time, hashlib, subprocess, shutil
    from pathlib import Path
    from datetime import datetime, timezone
    ROOT = Path('/content') / ('golf_coach_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
    ROOT.mkdir(parents=True, exist_ok=False)
    os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
    print('이번 실행 폴더:', ROOT)
    ''')
    md('''
    ## 1. 검증 도구 준비
    아래 셀에는 배포 패키지와 동일한 Python 검증·평가 도구가 포함되어 있습니다. 별도 설치 파일을 업로드할 필요가 없습니다.
    ''')
    embedded = []
    for name in ['coaching_training_helpers.py', 'prepare_coaching_dataset.py']:
        embedded.append(f'(ROOT / {name!r}).write_text({(HERE / name).read_text(encoding="utf-8")!r}, encoding="utf-8")')
    embedded.append('sys.path.insert(0, str(ROOT))')
    embedded.append('from prepare_coaching_dataset import prepare')
    embedded.append('from coaching_training_helpers import encode_completion, CompletionCollator, evaluate_model, MODEL_INPUT_VERSION')
    code('\n'.join(embedded))
    md('''
    ## 2. 지도자가 승인한 JSON 업로드
    앱에서 내보낸 파일에 골퍼/세션 식별자, 학습 사용 동의, 지도자 검토 결과를 채운 **JSON 여러 개**를 선택하세요.
    독립된 사람·촬영 세션 그룹이 최소 3개 필요합니다. 이 최소 개수는 프로그램 실행 조건이며 학습 품질을 보장하지 않습니다.
    미검토 예제 파일 하나만으로 학습하지 않습니다.
    ''')
    code('''
    from google.colab import files
    uploaded = files.upload()
    reviewed = ROOT / 'reviewed'
    reviewed.mkdir(exist_ok=False)
    if not uploaded or any(Path(name).suffix.lower() != '.json' for name in uploaded):
        raise ValueError('검토 JSON 파일만 선택하세요.')
    for name, data in uploaded.items():
        destination = reviewed / Path(name).name
        if destination.exists():
            raise ValueError('중복 파일명: ' + destination.name)
        destination.write_bytes(data)
    del uploaded
    prepared = ROOT / 'prepared'
    manifest = prepare(reviewed, prepared)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    ''')
    md('''
    ## 3. 라이브러리와 GPU 확인
    검증이 통과한 뒤에만 실행합니다. API 변동을 줄이기 위해 아래 버전을 고정했습니다. Colab이 제공하는 PyTorch/CUDA는 별도로 기록합니다.
    설치 후 재시작 안내가 나타나면 런타임을 재시작하고 위 셀부터 다시 실행하세요.
    ''')
    code('''
    assert (prepared / 'manifest.json').exists(), '데이터 검증을 먼저 완료하세요.'
    subprocess.run([sys.executable, '-m', 'pip', 'install', '-q',
        'transformers==4.56.2', 'peft==0.17.0', 'accelerate==1.10.1', 'bitsandbytes==0.47.0'], check=True)
    import torch
    import transformers, peft, accelerate, bitsandbytes
    assert torch.cuda.is_available(), 'GPU 런타임이 필요합니다.'
    from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig, Trainer, TrainingArguments, set_seed
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training, PeftModel
    from huggingface_hub import HfApi
    versions = {name: module.__version__ for name, module in {
        'torch': torch, 'transformers': transformers, 'peft': peft,
        'accelerate': accelerate, 'bitsandbytes': bitsandbytes}.items()}
    versions.update(cuda=torch.version.cuda, gpu=torch.cuda.get_device_name(0), python=sys.version)
    (ROOT / 'environment.json').write_text(json.dumps(versions, indent=2), encoding='utf-8')
    (ROOT / 'pip-freeze.txt').write_text(subprocess.check_output([sys.executable, '-m', 'pip', 'freeze'], text=True), encoding='utf-8')
    print(versions)
    ''')
    md('''
    ## 4. 기준 모델과 입력 길이 확인
    Qwen3-0.6B를 비추론 모드로 사용합니다. 4비트 NF4로 불러와 LoRA 파라미터만 학습할 예정입니다.
    너무 긴 자료는 잘라서 학습하지 않고 오류로 알립니다. 입력/정답을 누락시키지 않기 위함입니다.
    ''')
    code('''
    MODEL_ID = 'Qwen/Qwen3-0.6B'
    REVISION = HfApi().model_info(MODEL_ID).sha
    MAX_LENGTH = 4096
    SEED = 42
    set_seed(SEED)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, revision=REVISION, trust_remote_code=False)
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = 'right'
    rows = {name: [json.loads(line) for line in (prepared / f'{name}.jsonl').read_text(encoding='utf-8').splitlines() if line.strip()]
            for name in ['train', 'validation', 'test']}
    encoded = {name: [encode_completion(tokenizer, r, MAX_LENGTH) for r in records] for name, records in rows.items()}
    for name, records in encoded.items():
        print(name, '개수:', len(records), '최대 토큰:', max(len(r['input_ids']) for r in records))
    # Verify that only the answer, including EOS, contributes to the training loss.
    example = encoded['train'][0]
    answer_ids = [label for label in example['labels'] if label != -100]
    assert answer_ids[-1] == tokenizer.eos_token_id
    assert tokenizer.decode(answer_ids[:-1], skip_special_tokens=False) == rows['train'][0]['messages'][2]['content']
    print('정답 토큰 마스킹 확인 완료')
    use_bf16 = torch.cuda.is_bf16_supported()
    dtype = torch.bfloat16 if use_bf16 else torch.float16
    quantization = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type='nf4',
        bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=dtype)
    model = AutoModelForCausalLM.from_pretrained(MODEL_ID, revision=REVISION,
        quantization_config=quantization, torch_dtype=dtype, device_map={'': 0}, trust_remote_code=False)
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=False)
    run_config = {'model_id': MODEL_ID, 'revision': REVISION, 'model_input_version': MODEL_INPUT_VERSION,
                  'max_length': MAX_LENGTH, 'enable_thinking': False, 'seed': SEED,
                  'dataset_sha256': {n: hashlib.sha256((prepared / f'{n}.jsonl').read_bytes()).hexdigest() for n in rows}}
    (ROOT / 'run_config.json').write_text(json.dumps(run_config, indent=2), encoding='utf-8')
    ''')
    md('''
    ## 5. 학습 전 기준 평가
    검증 세트 전체를 평가합니다. JSON 형식, 근거 ID, 정답의 판단 종류, 판단 유보를 확인합니다.
    이 자동 점수는 교정 지식의 정확도 점수가 아닙니다. 생성 문장과 연습 방법은 지도자가 검토해야 합니다.
    ''')
    code('''
    reports = ROOT / 'reports'
    reports.mkdir(exist_ok=True)
    baseline_validation = evaluate_model(model, tokenizer, rows['validation'], reports / 'baseline_validation.jsonl')
    print(json.dumps(baseline_validation, ensure_ascii=False, indent=2))
    ''')
    md('''
    ## 6. QLoRA 추가 학습
    아래 설정은 첫 실험용입니다. 2 epoch가 최적이라는 의미는 아닙니다.
    기존 언어모델의 가중치는 고정하고 저차원 어댑터를 학습합니다. 입력 토큰과 패딩은 손실에서 제외합니다.
    검증 손실이 가장 낮은 epoch를 선택합니다. 테스트 세트는 학습/모델 선택에 사용하지 않습니다.
    ''')
    code('''
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True,
                                          gradient_checkpointing_kwargs={'use_reentrant': False})
    model = get_peft_model(model, LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05,
        target_modules='all-linear', bias='none', task_type='CAUSAL_LM'))
    model.config.use_cache = False
    model.print_trainable_parameters()
    arguments = TrainingArguments(
        output_dir=str(ROOT / 'checkpoints'), num_train_epochs=2,
        per_device_train_batch_size=1, per_device_eval_batch_size=1, gradient_accumulation_steps=8,
        learning_rate=1e-4, warmup_ratio=0.05, weight_decay=0.01,
        gradient_checkpointing=True, gradient_checkpointing_kwargs={'use_reentrant': False},
        bf16=use_bf16, fp16=not use_bf16, optim='adamw_torch',
        eval_strategy='epoch', save_strategy='epoch', save_total_limit=2,
        load_best_model_at_end=True, metric_for_best_model='eval_loss', greater_is_better=False,
        logging_steps=10, report_to=[], push_to_hub=False, seed=SEED, data_seed=SEED,
        dataloader_num_workers=0, label_names=['labels'])
    trainer = Trainer(model=model, args=arguments, train_dataset=encoded['train'],
        eval_dataset=encoded['validation'], data_collator=CompletionCollator(tokenizer.pad_token_id),
        processing_class=tokenizer)
    training = trainer.train()
    adapter = ROOT / 'adapter'
    trainer.save_model(str(adapter))
    tokenizer.save_pretrained(str(adapter))
    (ROOT / 'training_metrics.json').write_text(json.dumps(training.metrics, indent=2), encoding='utf-8')
    (ROOT / 'training_arguments.json').write_text(arguments.to_json_string(), encoding='utf-8')
    model = trainer.model
    model.gradient_checkpointing_disable()
    model.config.use_cache = True
    print('어댑터 저장:', adapter)
    ''')
    md('''
    ## 7. 학습 후 비교 및 별도 테스트
    동일한 4비트 모델에서 어댑터를 켜고 끄며 비교합니다. 테스트 결과를 보고 반복 튜닝하면 더 이상 독립 테스트가 아니므로, 새 평가 그룹을 확보해야 합니다.
    검토자는 reports의 reference/prediction과 원본 영상을 함께 확인하세요. 임의 숫자, 잘못된 원인 단정, 부적합한 연습은 자동 점수가 좋아도 탈락입니다.
    ''')
    code('''
    adapted_validation = evaluate_model(model, tokenizer, rows['validation'], reports / 'adapted_validation.jsonl')
    with model.disable_adapter():
        baseline_test = evaluate_model(model, tokenizer, rows['test'], reports / 'baseline_test.jsonl')
    adapted_test = evaluate_model(model, tokenizer, rows['test'], reports / 'adapted_test.jsonl')
    comparison = {'baseline_validation': baseline_validation, 'adapted_validation': adapted_validation,
                  'baseline_test': baseline_test, 'adapted_test': adapted_test,
                  'deployment_approved': False, 'reason': '지도자 검토 및 폰 검증 전'}
    (reports / 'comparison.json').write_text(json.dumps(comparison, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(comparison, ensure_ascii=False, indent=2))
    ''')
    md('''
    ## 8. 실험 결과 보관
    어댑터·검증 결과·실행 버전·데이터 분할 명세를 ZIP으로 내려받습니다. 교정 모델의 배포 승인을 의미하지 않습니다.
    JSONL 보고서에는 업로드한 측정 수치와 정답이 포함됩니다.
    ''')
    code('''
    bundle = ROOT / 'experiment_bundle'
    bundle.mkdir(exist_ok=True)
    shutil.copytree(adapter, bundle / 'adapter', dirs_exist_ok=True)
    shutil.copytree(reports, bundle / 'reports', dirs_exist_ok=True)
    for name in ['environment.json', 'pip-freeze.txt', 'run_config.json', 'training_metrics.json', 'training_arguments.json']:
        shutil.copy2(ROOT / name, bundle / name)
    shutil.copy2(prepared / 'manifest.json', bundle / 'dataset_manifest.json')
    for name in ['coaching_training_helpers.py', 'prepare_coaching_dataset.py']:
        shutil.copy2(ROOT / name, bundle / name)
    archive = shutil.make_archive(str(ROOT / 'golf_coaching_experiment'), 'zip', bundle)
    files.download(archive)
    ''')
    md('''
    ## 9. 선택: FP16 병합 및 GGUF 4비트 파일 생성
    폰에서 시험할 파일을 만드는 단계입니다. NF4 학습 가중치를 직접 병합하지 않고 **동일 revision의 원래 FP16 모델**에 어댑터를 병합합니다.
    GGUF Q4_K_M은 학습의 NF4와 다른 양자화입니다. 변환 후 답변 품질을 다시 확인해야 합니다.
    아래 셀은 llama.cpp 다운로드와 빌드로 시간이 추가됩니다. `EXPORT_GGUF=True`로 바꿀 때 실행합니다.
    생성 파일은 실험용이며 앱에 자동 설치하거나 공개하지 않습니다.
    ''')
    code('''
    EXPORT_GGUF = False
    if EXPORT_GGUF:
        import gc
        del trainer, model
        gc.collect()
        torch.cuda.empty_cache()
        original = AutoModelForCausalLM.from_pretrained(MODEL_ID, revision=REVISION,
            torch_dtype=torch.float16, device_map={'': 'cpu'}, trust_remote_code=False)
        merged = PeftModel.from_pretrained(original, str(adapter)).merge_and_unload()
        merged_dir = ROOT / 'merged_fp16'
        merged.save_pretrained(merged_dir, safe_serialization=True)
        tokenizer.save_pretrained(merged_dir)
        del merged, original
        gc.collect()
        llama = ROOT / 'llama.cpp'
        subprocess.run(['git', 'clone', '--depth', '1', 'https://github.com/ggml-org/llama.cpp.git', str(llama)], check=True)
        llama_revision = subprocess.check_output(['git', '-C', str(llama), 'rev-parse', 'HEAD'], text=True).strip()
        converter_env = ROOT / 'gguf_environment'
        subprocess.run([sys.executable, '-m', 'venv', str(converter_env)], check=True)
        converter_python = str(converter_env / 'bin/python')
        subprocess.run([converter_python, '-m', 'pip', 'install', '-r', str(llama / 'requirements/requirements-convert_hf_to_gguf.txt')], check=True)
        (ROOT / 'gguf_pip_freeze.txt').write_text(subprocess.check_output(
            [converter_python, '-m', 'pip', 'freeze'], text=True), encoding='utf-8')
        subprocess.run(['cmake', '-S', str(llama), '-B', str(llama / 'build'),
                        '-DCMAKE_BUILD_TYPE=Release', '-DGGML_CUDA=OFF', '-DLLAMA_CURL=OFF'], check=True)
        subprocess.run(['cmake', '--build', str(llama / 'build'), '--config', 'Release',
                        '--target', 'llama-quantize', '-j', '2'], check=True)
        fp16 = ROOT / 'golf-coach-f16.gguf'
        quantized = ROOT / 'golf-coach-q4_k_m.gguf'
        subprocess.run([converter_python, str(llama / 'convert_hf_to_gguf.py'), str(merged_dir),
                        '--outfile', str(fp16), '--outtype', 'f16'], check=True)
        subprocess.run([str(llama / 'build/bin/llama-quantize'), str(fp16), str(quantized), 'Q4_K_M'], check=True)
        with quantized.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        export_manifest = {'llama_cpp_revision': llama_revision, 'base_revision': REVISION,
            'quantization': 'Q4_K_M', 'model_input_version': MODEL_INPUT_VERSION,
            'sha256': digest, 'bytes': quantized.stat().st_size,
            'phone_tested': False, 'deployment_approved': False}
        (ROOT / 'gguf_manifest.json').write_text(json.dumps(export_manifest, indent=2), encoding='utf-8')
        files.download(str(quantized))
        files.download(str(ROOT / 'gguf_manifest.json'))
    else:
        print('GGUF 변환은 실행하지 않았습니다. 실험 결과를 검토한 뒤 선택하세요.')
    ''')
    md('''
    ## 폰 탑재 전 확인할 것
    - 앱 입력도 `coaching_training_helpers.model_input`과 동일한 `golf_coaching_input_1.0` 형식으로 변환해야 합니다.
    - 비추론 chat template와 JSON 출력 검증을 유지합니다. 형식 실패나 근거 부족일 때는 검토 안내로 대체합니다.
    - 실제 폰에서 Q4 답변을 다시 평가하고 지연 시간, 최대 메모리, 반복 실행 발열을 측정합니다.
    - Colab 속도/정확도 수치를 폰 성능으로 보고하지 않습니다.

    참고: [Qwen3 모델](https://huggingface.co/Qwen/Qwen3-0.6B),
    [PEFT 양자화 학습](https://huggingface.co/docs/peft/v0.17.0/en/developer_guides/quantization),
    [Transformers Trainer](https://huggingface.co/docs/transformers/v4.56.2/en/main_classes/trainer),
    [llama.cpp](https://github.com/ggml-org/llama.cpp).
    ''')
    for i, cell in enumerate(cells):
        cell['id'] = f'golf-cell-{i:02}'
    notebook = {'nbformat': 4, 'nbformat_minor': 5, 'cells': cells,
                'metadata': {'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'},
                             'language_info': {'name': 'python', 'version': '3.11'},
                             'colab': {'name': 'golf_coaching_qlora.ipynb', 'provenance': []}}}
    Path(destination).write_text(json.dumps(notebook, ensure_ascii=False, indent=2), encoding='utf-8')
    return notebook


if __name__ == '__main__':
    import sys
    build(sys.argv[1])
