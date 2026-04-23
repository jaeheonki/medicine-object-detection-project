import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))

import torch
from torch.utils.data import DataLoader
from torchvision import transforms

from src.annotation_mapping import run_annotation_mapping
from src.dataset import PillDataset, PillTestDataset, collate_fn
from src.preprocessing_basic import make_dataloaders
from src.model_utils import train, predict, plot_history, plot_predictions
from models.ssd_model import build_tuned_ssd, SSDTwoStageFinetuner, DEVICE, NUM_CLASSES

# =============================================================================
# 1. 경로 설정
# =============================================================================
DATA_ROOT      = PROJECT_ROOT / "data"         # 다운로드 압축 해제 대상 폴더
MERGED_ANN_DIR = PROJECT_ROOT / "data" / "merged_annotations"

MODEL_NAME = "ssd_resnet50"

# =============================================================================
# 2. 하이퍼파라미터
# =============================================================================
BATCH_SIZE     = 4
TRAIN_RATIO    = 0.8
STAGE1_EPOCHS  = 40
STAGE2_EPOCHS  = 60
STAGE1_LR      = 1e-4
STAGE2_LR      = 1e-4
WEIGHT_DECAY   = 1e-4
INPUT_SIZE     = 300


# =============================================================================
# 히스토리 병합
# =============================================================================
def merge_histories(h1: dict, h2: dict) -> dict:
    """Stage 1, Stage 2 history를 하나로 합쳐 반환."""
    return {
        'train_loss': h1['train_loss'] + h2['train_loss'],
        'val_map':    h1['val_map']    + h2['val_map'],
        'val_map_50': h1['val_map_50'] + h2['val_map_50'],
        'val_f1':     h1['val_f1']     + h2['val_f1'],
        'time':       h1['time']       + h2['time'],
    }


def print_best_summary(history: dict, stage: str, epoch_offset: int = 0) -> None:
    """학습 종료 후 best mAP / mAP@50 / F1 과 해당 epoch를 출력.
    epoch_offset: Stage 2에서 전체 기준 epoch 번호를 표시하기 위해 더할 값.
    """
    best_map_val   = max(history['val_map'])
    best_map50_val = max(history['val_map_50'])
    best_f1_val    = max(history['val_f1'])

    best_map_ep   = history['val_map'].index(best_map_val)      + 1 + epoch_offset
    best_map50_ep = history['val_map_50'].index(best_map50_val) + 1 + epoch_offset
    best_f1_ep    = history['val_f1'].index(best_f1_val)        + 1 + epoch_offset

    print(f"\n[{stage} 결과]")
    print(f"  best mAP    : {best_map_val:.4f}  (Epoch {best_map_ep:02d})")
    print(f"  best mAP@50 : {best_map50_val:.4f}  (Epoch {best_map50_ep:02d})")
    print(f"  best F1     : {best_f1_val:.4f}  (Epoch {best_f1_ep:02d})")


# =============================================================================
# 데이터 다운로드 및 경로 자동 탐지
# =============================================================================
def download_if_needed() -> Path:
    """
    train_annotations 폴더가 없으면 구글 드라이브에서 다운로드 후 압축 해제.
    실제 데이터 루트(train_annotations의 부모) 경로를 반환.
    """
    found = list(DATA_ROOT.rglob("train_annotations"))
    if found:
        print(f"기존 데이터 확인: {found[0]}")
        return found[0].parent

    print("데이터 없음 — 구글 드라이브에서 다운로드 시작...")
    from utils import download_data
    download_data(str(DATA_ROOT))

    found = list(DATA_ROOT.rglob("train_annotations"))
    if not found:
        raise FileNotFoundError(
            "다운로드 후에도 train_annotations 폴더를 찾을 수 없습니다. "
            "압축 파일 구조를 확인하세요."
        )
    print(f"다운로드 완료: {found[0]}")
    return found[0].parent


def detect_image_dirs(data_root: Path) -> tuple[Path, Path]:
    """
    data_root 하위에서 학습/테스트 이미지 폴더를 탐지해 반환.
    폴더명이 다를 수 있어 후보 이름 목록으로 순차 탐색.
    """
    train_candidates = ["train_images", "train", "images/train"]
    test_candidates  = ["test_images",  "test",  "images/test"]

    train_img_dir = next(
        (data_root / c for c in train_candidates if (data_root / c).is_dir()), None
    )
    test_img_dir = next(
        (data_root / c for c in test_candidates if (data_root / c).is_dir()), None
    )

    if train_img_dir is None:
        raise FileNotFoundError(f"학습 이미지 폴더를 찾을 수 없습니다: {data_root}")
    if test_img_dir is None:
        raise FileNotFoundError(f"테스트 이미지 폴더를 찾을 수 없습니다: {data_root}")

    return train_img_dir, test_img_dir


# =============================================================================
# 메인 파이프라인
# =============================================================================
def main():
    print(f"Device: {DEVICE}")
    print(f"Torch: {torch.__version__} | CUDA: {torch.cuda.is_available()}")

    # =========================================================================
    # 3. 데이터 다운로드 & 경로 탐지
    # =========================================================================
    sprint_root   = download_if_needed()
    train_ann_dir = sprint_root / "train_annotations"
    train_img_dir, test_img_dir = detect_image_dirs(sprint_root)

    print(f"어노테이션: {train_ann_dir}")
    print(f"학습 이미지: {train_img_dir}")
    print(f"테스트 이미지: {test_img_dir}")

    # =========================================================================
    # 4. Annotation Mapping
    #    merged_annotations 폴더가 없거나 비어있으면 병합 실행
    # =========================================================================
    if not MERGED_ANN_DIR.exists() or not any(MERGED_ANN_DIR.glob("*.json")):
        print("\n어노테이션 병합 시작...")
        result = run_annotation_mapping(train_ann_dir, MERGED_ANN_DIR)
        print(f"병합 완료: {len(result['saved_paths'])}개 | 실패: {len(result['failed_files'])}개")
    else:
        n_merged = len(list(MERGED_ANN_DIR.glob("*.json")))
        print(f"\n기존 병합 어노테이션 사용: {n_merged}개")

    # =========================================================================
    # 5. Transform
    #    SSD 모델이 내부적으로 ImageNet 정규화와 리사이즈(300×300)를 처리하므로
    #    Dataset에서는 ToTensor만 적용
    # =========================================================================
    ssd_transform = transforms.Compose([
        transforms.ToTensor(),
    ])

    # =========================================================================
    # 6. Dataset & DataLoader
    # =========================================================================
    dataset = PillDataset(
        ann_dir=MERGED_ANN_DIR,
        image_dir=train_img_dir,
        transform=ssd_transform,
    )
    print(f"\nDataset 크기: {len(dataset)} | 클래스 수: {len(dataset.category_map)}")

    train_loader, val_loader = make_dataloaders(
        dataset,
        batch_size=BATCH_SIZE,
        train_ratio=TRAIN_RATIO,
        val_ratio=round(1.0 - TRAIN_RATIO, 1),
    )
    print(f"Train batches: {len(train_loader)} | Val batches: {len(val_loader)}")

    # =========================================================================
    # 7. 모델 빌드
    # =========================================================================
    model = build_tuned_ssd(num_classes=NUM_CLASSES, input_size=INPUT_SIZE)
    finetuner = SSDTwoStageFinetuner(model)
    total_params = sum(p.numel() for p in model.parameters())
    print(f"\n총 파라미터: {total_params:,}")

    # =========================================================================
    # 8. Stage 1 학습 — ResNet backbone frozen, extra_layers + SSDHead만 학습
    #    권장: 10~15 epoch, lr=1e-3
    # =========================================================================
    print("\n" + "=" * 60)
    print("Stage 1: backbone frozen, extra_layers + head 학습")
    print("=" * 60)
    finetuner.stage1_freeze_backbone()

    history_s1 = train(
        model=model,
        model_name=MODEL_NAME,
        train_loader=train_loader,
        val_loader=val_loader,
        epochs=STAGE1_EPOCHS,
        lr=STAGE1_LR,
        wd=WEIGHT_DECAY,
        model_type='torchvision',
    )
    s1_actual_epochs = len(history_s1['val_map'])
    print_best_summary(history_s1, "Stage 1")

    # =========================================================================
    # 9. Stage 2 학습 — layer3/4/extra_layers unfreeze, 점진적 도메인 적응
    #    권장: 20~30 epoch, lr=1e-4
    # =========================================================================
    print("\n" + "=" * 60)
    print("Stage 2: layer3/4/extra_layers unfreeze, fine-tuning")
    print("=" * 60)
    finetuner.stage2_unfreeze_partial()

    history_s2 = train(
        model=model,
        model_name=MODEL_NAME,
        train_loader=train_loader,
        val_loader=val_loader,
        epochs=STAGE2_EPOCHS,
        lr=STAGE2_LR,
        wd=WEIGHT_DECAY,
        model_type='torchvision',
    )
    print_best_summary(history_s2, "Stage 2", epoch_offset=s1_actual_epochs)

    total_minutes = (history_s1['time'] + history_s2['time']) / 60
    print(f"[총 학습시간 : {total_minutes:.1f}분]")

    # =========================================================================
    # 10. 학습 곡선 시각화
    #     전체 합친 그래프 + 스테이지별 그래프 저장
    # =========================================================================
    history_all = merge_histories(history_s1, history_s2)
    plot_history(history_all, model_name=f"{MODEL_NAME}_all")
    plot_history(history_s1,  model_name=f"{MODEL_NAME}_stage1")
    plot_history(history_s2,  model_name=f"{MODEL_NAME}_stage2")

    # =========================================================================
    # 11. 예측 결과 시각화 (best 모델 로드 후 val 샘플 5장)
    # =========================================================================
    val_dataset = val_loader.dataset  # random_split Subset
    plot_predictions(model, val_dataset, model_name=MODEL_NAME, n=5)

    # =========================================================================
    # 12. 테스트 예측 및 제출 파일 생성
    #     outputs/{MODEL_NAME}_submission.csv 저장
    # =========================================================================
    test_dataset = PillTestDataset(
        image_dir=test_img_dir,
        transform=ssd_transform,
    )
    print(f"\n테스트 Dataset 크기: {len(test_dataset)}")

    test_loader = DataLoader(
        test_dataset,
        batch_size=BATCH_SIZE,
        shuffle=False,
        num_workers=0,
        pin_memory=True,
        collate_fn=collate_fn,
    )

    submission_df = predict(
        model=model,
        test_loader=test_loader,
        model_name=MODEL_NAME,
        score_threshold=0.5,
        model_type='torchvision',
    )
    print(f"제출 파일 완료: {len(submission_df)}개 탐지")


if __name__ == "__main__":
    main()
