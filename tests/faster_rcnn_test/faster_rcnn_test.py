import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from src.annotation_mapping import run_annotation_mapping
from src.utils import download_data
from src.model_utils import train, plot_history, plot_predictions
from src.dataset import PillDataset, collate_fn
from src.preprocessing_basic import basic_transform, make_dataloaders
import json

if __name__ == "__main__":
    # 1. 데이터 다운로드 (이미 존재하면 스킵)
    if not os.path.exists("data/sprint_ai_project1_data"):
        download_data(extract_path="./data")

    # 2. 어노테이션 매핑 (이미 존재하면 스킵)
    if not os.path.exists("data/merged_annotations"):
        result = run_annotation_mapping(
            annotation_root_dir="data/sprint_ai_project1_data/train_annotations",
            output_dir="data/merged_annotations"
        )
        print("파싱 성공 JSON 수:", len(result["parsed_list"]))
        print("파싱 실패 JSON 수:", len(result["failed_files"]))
        print("병합 후 이미지 수:", len(result["merged_results"]))
        print("저장된 merged annotation 수:", len(result["saved_paths"]))

    # 3. 데이터셋 생성
    dataset = PillDataset(
        ann_dir="data/merged_annotations",
        image_dir="data/sprint_ai_project1_data/train_images",
        transform=basic_transform()
    )
    print(f"데이터셋 크기: {len(dataset)}")

    # 4. 데이터로더 생성 (70:30, seed=42)
    train_loader, val_loader = make_dataloaders(
        dataset=dataset,
        batch_size=4,
        train_ratio=0.7,
        val_ratio=0.3,
        seed=42
    )

    # 5. 모델 생성
    from models.Faster_R_CNN_model import build_tuned_faster_rcnn
    model = build_tuned_faster_rcnn(num_classes=57)

    # 6. 학습 (체크포인트 있으면 스킵)
    if not os.path.exists("checkpoints/faster_rcnn.pt"):
        history = train(
            model=model,
            model_name="faster_rcnn",
            train_loader=train_loader,
            val_loader=val_loader,
            epochs=100,
            lr=1e-4,
            wd=1e-4,
            model_type="torchvision",
        )
    else:
        print("체크포인트 존재 → 학습 스킵")
        with open("outputs/faster_rcnn_history.json", "r") as f:
            history = json.load(f)

    # 7. 학습 곡선 시각화
    plot_history(history, model_name="faster_rcnn")

    # 8. 예측 결과 시각화 (val 데이터셋에서 5장 샘플링)
    plot_predictions(model, dataset, model_name="faster_rcnn", n=5)