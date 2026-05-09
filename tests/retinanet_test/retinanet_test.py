import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.annotation_mapping import run_annotation_mapping
from src.utils import download_data
from src.model_utils import train, evaluate, predict, plot_history, load_model, plot_predictions
from src.preprocessing_basic import basic_transform, make_dataloaders
from src.dataset import PillDataset, PillTestDataset, collate_fn


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
    # merged_annotations 폴더와 이미지 폴더를 기반으로 Dataset 생성
    dataset = PillDataset(
        ann_dir="data/merged_annotations",
        image_dir="data/sprint_ai_project1_data/train_images",
        transform=basic_transform()
    )
    print(f"데이터셋 크기: {len(dataset)}")

    # 4. 데이터로더 생성
    # train 70%, val 30%으로 분할
    train_loader, val_loader = make_dataloaders(
        dataset=dataset,
        batch_size=4,
        train_ratio=0.7,
        val_ratio=0.3,
        seed=42
    )

    # 5. 모델 생성
    from models.retinanet import build_retinanet
    model = build_retinanet(num_classes=57)

    # 6. 학습 (체크포인트가 이미 있으면 스킵)
    import json
    if not os.path.exists("checkpoints/retinanet.pt"):
        retina_history = train(
            model=model,
            model_name="retinanet",
            train_loader=train_loader,
            val_loader=val_loader,
            epochs=100,
            lr=1e-4,
            wd=1e-4,
            model_type="torchvision",
        )
    else:
        print("체크포인트 존재 → 학습 스킵")
        with open("outputs/retinanet_history.json", "r") as f:
            retina_history = json.load(f)

    # 7. 학습 곡선 시각화
    plot_history(retina_history, model_name="retinanet")

    # 8. 예측 결과 시각화 (val 데이터셋에서 5장 샘플링)
    plot_predictions(model, dataset, model_name="retinanet", n=5)
