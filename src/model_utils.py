import torch
import os
import time
import json
import random
import numpy as np
import pandas as pd
import matplotlib
import yaml
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from pathlib import Path
from torchmetrics.detection.mean_ap import MeanAveragePrecision
from torchvision.ops import box_iou
from ultralytics import YOLO

# GPU/CPU 설정
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

# %% 모델 학습 함수
def train(model, model_name, train_loader, val_loader, epochs, lr, wd, model_type='torchvision'):
    model = model.to(device)

    # AdamW 옵티마이저 설정
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=wd)

    # CosineAnnealing 스케줄러 설정
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs, eta_min=1e-6)

    # 학습 기록 초기화
    history = {'train_loss': [], 'val_map': [], 'val_map_50': [], 'val_f1': [], 'time': 0.0}
    best_map = 0.0
    early_stop_counter = 0
    patience = 10
    os.makedirs('checkpoints', exist_ok=True)

    start_time = time.time()
    print(f"학습 시작 | 모델: {model_name} | Epochs: {epochs} | LR: {lr} | Device: {device}")

    for epoch in range(epochs):
        # 학습 단계
        model.train()
        train_loss = 0.0
        for batch_idx, (images, targets) in enumerate(train_loader):
            images = [img.to(device) for img in images]
            targets = [{k: v.to(device) for k, v in t.items()} for t in targets]

            # HuggingFace 계열 (DETR 등): pixel_values, labels 형식으로 입력
            if model_type == 'huggingface':
                output = model(pixel_values=images, labels=targets)
                loss = output.loss
            else:
                # torchvision 계열 (Faster R-CNN, SSD, RetinaNet 등): dict로 loss 반환
                output = model(images, targets)
                loss = sum(output.values())

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += loss.item()
            if (batch_idx + 1) % 8 == 0:
                print(".", end="", flush=True)

        train_loss /= len(train_loader)

        # 검증 단계
        val_map, val_map_50, val_f1 = evaluate(model, val_loader, model_type)

        # 스케줄러 업데이트
        scheduler.step()

        # 기록 업데이트
        history['train_loss'].append(train_loss)
        history['val_map'].append(val_map)
        history['val_map_50'].append(val_map_50)
        history['val_f1'].append(val_f1)

        print(f"Epoch [{epoch+1}/{epochs}] | Train Loss: {train_loss:.4f} | Val mAP: {val_map:.4f} | Val mAP@50: {val_map_50:.4f} | Val F1: {val_f1:.4f}")

        # best 모델 저장
        if val_map > best_map:
            best_map = val_map
            early_stop_counter = 0
            torch.save(model.state_dict(), f'checkpoints/{model_name}.pt')
            print(f"  -> Best model saved (mAP: {best_map:.4f})")
        else:
            # early stopping 카운터 증가
            early_stop_counter += 1
            if early_stop_counter >= patience:
                print(f"Early stopping at epoch {epoch+1}")
                break

    # 총 학습 시간 기록
    history['time'] = time.time() - start_time

    # history를 json 파일로 저장
    os.makedirs('outputs', exist_ok=True)
    with open(f'outputs/{model_name}_history.json', 'w') as f:
        json.dump(history, f, indent=4)

    return history


# %% 검증 함수
def evaluate(model, val_loader, model_type='torchvision'):
    model.eval()

    # mAP 계산기 초기화 (엄격 기준: 0.75~0.95, 완화 기준: 0.5 별도)
    metric = MeanAveragePrecision(iou_thresholds=[0.75, 0.80, 0.85, 0.90, 0.95], extended_summary=False)
    metric_50 = MeanAveragePrecision(iou_thresholds=[0.50], extended_summary=False)

    all_preds = []
    all_targets = []

    with torch.no_grad():
        for images, targets in val_loader:
            images = [img.to(device) for img in images]
            targets = [{k: v.to(device) for k, v in t.items()} for t in targets]

            # 모델 예측 (eval 모드에서는 loss 없이 예측값만 반환)
            if model_type == 'huggingface':
                output = model(pixel_values=images)
                # DETR 출력: logits(클래스), pred_boxes(cx,cy,w,h 정규화 좌표)
                prob = output.logits.softmax(-1)
                # 마지막 클래스는 "no object" → 제외
                scores, labels = prob[..., :-1].max(-1)
                # 정규화된 cx,cy,w,h → 절대 좌표 x1,y1,x2,y2 변환
                h, w = images[0].shape[-2], images[0].shape[-1]
                boxes = output.pred_boxes
                cx, cy, bw, bh = boxes[..., 0], boxes[..., 1], boxes[..., 2], boxes[..., 3]
                x1 = (cx - bw / 2) * w
                y1 = (cy - bh / 2) * h
                x2 = (cx + bw / 2) * w
                y2 = (cy + bh / 2) * h
                abs_boxes = torch.stack([x1, y1, x2, y2], dim=-1)
                preds = [{'boxes': abs_boxes[i].cpu(), 'scores': scores[i].cpu(), 'labels': labels[i].cpu()} for i in range(len(images))]
            else:
                preds = model(images)

            # torchmetrics 형식으로 변환
            for pred, target in zip(preds, targets):
                all_preds.append({
                    'boxes': pred['boxes'].cpu(),
                    'scores': pred['scores'].cpu(),
                    'labels': pred['labels'].cpu(),
                })
                all_targets.append({
                    'boxes': target['boxes'].cpu(),
                    'labels': target['labels'].cpu(),
                })

    # mAP 계산
    metric.update(all_preds, all_targets)  # ty: ignore[invalid-argument-type]
    metric_50.update(all_preds, all_targets)  # ty: ignore[invalid-argument-type]
    result = metric.compute()  # ty: ignore[missing-argument]
    result_50 = metric_50.compute()  # ty: ignore[missing-argument]

    val_map = result['map'].item()           # mAP@0.75:0.95
    val_map_50 = result_50['map_50'].item()  # mAP@0.5

    # IoU 기반 TP/FP/FN 계산으로 정확한 precision/recall 산출
    precision, recall = calc_precision_recall(all_preds, all_targets)
    val_f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0

    return val_map, val_map_50, val_f1


# %% IoU 기반 precision/recall 계산 함수
def calc_precision_recall(preds, targets, iou_threshold=0.5, score_threshold=0.5):
    tp, fp, fn = 0, 0, 0

    for pred, target in zip(preds, targets):
        # score threshold 이상인 예측 박스만 사용
        scores = pred['scores']
        keep = scores >= score_threshold
        pred_boxes = pred['boxes'][keep]
        gt_boxes = target['boxes']

        if len(pred_boxes) == 0 and len(gt_boxes) == 0:
            continue
        elif len(pred_boxes) == 0:
            # 예측 없음 → 정답 박스 수만큼 FN
            fn += len(gt_boxes)
            continue
        elif len(gt_boxes) == 0:
            # 정답 없음 → 예측 박스 수만큼 FP
            fp += len(pred_boxes)
            continue

        # 예측 박스와 정답 박스 간 IoU 계산
        iou = box_iou(pred_boxes, gt_boxes)

        matched_gt = set()  # 이미 매칭된 정답 박스 인덱스 추적
        for pred_idx in range(len(pred_boxes)):
            # 현재 예측 박스와 각 정답 박스의 IoU 중 가장 높은 것 선택
            best_iou, best_gt_idx = iou[pred_idx].max(dim=0)

            if best_iou >= iou_threshold and best_gt_idx.item() not in matched_gt:
                # IoU 조건 만족 + 아직 매칭 안 된 정답 박스 → TP
                tp += 1
                matched_gt.add(best_gt_idx.item())
            else:
                # 조건 미충족 or 이미 매칭된 정답 박스 → FP
                fp += 1

        # 매칭되지 않은 정답 박스 수 = FN
        fn += len(gt_boxes) - len(matched_gt)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    return precision, recall


# %% 학습 곡선 시각화 함수
def plot_history(history, model_name="model"):
    epochs = range(1, len(history['train_loss']) + 1)

    _, axes = plt.subplots(1, 3, figsize=(15, 4))

    # Train Loss
    axes[0].plot(epochs, history['train_loss'], 'b-', label='Train Loss')
    axes[0].set_title('Train Loss')
    axes[0].set_xlabel('Epoch')
    axes[0].set_ylabel('Loss')
    axes[0].legend()

    # Val mAP
    axes[1].plot(epochs, history['val_map'], 'g-', label='mAP@0.75:0.95')
    axes[1].plot(epochs, history['val_map_50'], 'g--', label='mAP@0.5')
    axes[1].set_title('Validation mAP')
    axes[1].set_xlabel('Epoch')
    axes[1].set_ylabel('mAP')
    axes[1].legend()

    # Val F1
    axes[2].plot(epochs, history['val_f1'], 'r-', label='Val F1')
    axes[2].set_title('Validation F1')
    axes[2].set_xlabel('Epoch')
    axes[2].set_ylabel('F1')
    axes[2].legend()

    plt.suptitle(f'{model_name} Training History')
    plt.tight_layout()
    os.makedirs('outputs', exist_ok=True)
    plt.savefig(f'outputs/{model_name}_history.png')
    plt.show()


# %% 모델 로드 함수
def load_model(model, model_name):
    checkpoint_path = f'checkpoints/{model_name}.pt'
    model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
    model.to(device)
    return model


# %% 예측 결과 시각화 함수
def plot_predictions(model, dataset, model_name="model", n=5):
    # best 모델 가중치 로드
    model = load_model(model, model_name)
    model.eval()

    # 랜덤으로 n장 샘플링
    indices = random.sample(range(len(dataset)), n)

    _, axes = plt.subplots(n, 3, figsize=(15, n * 4))

    with torch.no_grad():
        for row, idx in enumerate(indices):
            image, target = dataset[idx]
            image_tensor = image.unsqueeze(0).to(device)

            # 모델 예측
            pred = model(image_tensor)[0]

            # 텐서를 numpy로 변환 (H, W, C)
            img_np = image.permute(1, 2, 0).cpu().numpy()
            img_np = np.clip(img_np, 0, 1)

            # 원본 이미지
            axes[row, 0].imshow(img_np)
            axes[row, 0].set_title('Original')
            axes[row, 0].axis('off')

            # 예측 박스 (정답과 IoU 매칭 후 라벨 일치 여부로 색상 결정)
            axes[row, 1].imshow(img_np)
            gt_boxes = target['boxes'].cpu()
            gt_labels = target['labels'].cpu()
            for box, score, label in zip(pred['boxes'].cpu(), pred['scores'].cpu(), pred['labels'].cpu()):
                if score < 0.5:
                    continue
                x1, y1, x2, y2 = box
                color = 'red'
                if len(gt_boxes) > 0:
                    iou = box_iou(box.unsqueeze(0), gt_boxes)[0]
                    best_idx = iou.argmax().item()
                    if iou[best_idx] >= 0.5 and gt_labels[best_idx].item() == label.item():
                        color = 'green'
                rect = patches.Rectangle((x1, y1), x2-x1, y2-y1, linewidth=2, edgecolor=color, facecolor='none')
                axes[row, 1].add_patch(rect)
                axes[row, 1].text(x1, y1, f'cls:{label.item()} {score:.2f}', color=color, fontsize=8)
            axes[row, 1].set_title('Prediction (green=correct, red=wrong)')
            axes[row, 1].axis('off')

            # 정답 박스
            axes[row, 2].imshow(img_np)
            for box, label in zip(target['boxes'].cpu(), target['labels'].cpu()):
                x1, y1, x2, y2 = box
                rect = patches.Rectangle((x1, y1), x2-x1, y2-y1, linewidth=2, edgecolor='green', facecolor='none')
                axes[row, 2].add_patch(rect)
                axes[row, 2].text(x1, y1, f'cls:{label.item()}', color='green', fontsize=8)
            axes[row, 2].set_title('Ground Truth')
            axes[row, 2].axis('off')

    plt.suptitle(f'{model_name} Predictions')
    plt.tight_layout()
    os.makedirs('outputs', exist_ok=True)
    plt.savefig(f'outputs/{model_name}_predictions.png')
    plt.show()

# 원본 카테고리 아이디와 매핑
def make_category_map(yaml_path, annotation_dir):
    """
    YOLO class id -> 원본 category_id 매핑 생성
    """
    with open(yaml_path, "r", encoding="utf-8") as f:
        names = yaml.safe_load(f)["names"]

    # YOLO class id -> 약 이름
    yolo_id_to_name = {
        i: " ".join(str(name).replace("\xa0", " ").split())
        for i, name in enumerate(names)
    }

    # 약 이름 -> 원본 category_id
    name_to_category_id = {}

    for json_path in Path(annotation_dir).rglob("*.json"):
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        categories = data.get("raw_categories", data.get("categories", []))

        for cat in categories:
            name = " ".join(str(cat["name"]).replace("\xa0", " ").split())
            name_to_category_id[name] = int(cat["id"])

    # YOLO class id -> 원본 category_id
    return {
        class_id: name_to_category_id[name]
        for class_id, name in yolo_id_to_name.items()
    }

# %% 제출용 예측 함수
def make_yolo_submission(save_dir):
    """
    YOLO best_map75_95.pt로 test image 예측 후 제출 CSV 생성
    save_dir: train() 함수가 반환하는 save_dir 경로
    """
    PROJECT_ROOT = Path("/content/medicine-object-detection-project")
    save_dir = Path(save_dir)
    # mAP@0.75:0.95 기준 베스트 모델 우선 로드, 없으면 YOLO 기본 best.pt 사용
    model_path = save_dir / "weights" / "best_map75_95.pt"
    if not model_path.exists():
        model_path = save_dir / "weights" / "best.pt"
    test_image_dir=PROJECT_ROOT / "data" / "sprint_ai_project1_data" / "test_images"
    yaml_path=PROJECT_ROOT / "data" / "yolo_dataset" / "dataset.yaml"
    annotation_dir=PROJECT_ROOT / "data" / "merged_annotations"
    output_csv_path=PROJECT_ROOT / "submission" / "yolo11s_submission.csv"
    score_threshold=0.5

    class_id_to_category_id = make_category_map(yaml_path, annotation_dir)

    model = YOLO(str(model_path))

    image_paths = (
        list(Path(test_image_dir).glob("*.jpg"))
        + list(Path(test_image_dir).glob("*.jpeg"))
        + list(Path(test_image_dir).glob("*.png"))
    )

    image_paths = sorted(image_paths, key=lambda p: int(p.stem))

    rows = []
    annotation_id = 1

    for image_path in image_paths:
        image_id = int(image_path.stem)

        result = model.predict(
            source=str(image_path),
            conf=score_threshold,
            verbose=False,
        )[0]

        if result.boxes is None:
            continue

        boxes = result.boxes.xyxy.cpu()
        scores = result.boxes.conf.cpu()
        labels = result.boxes.cls.cpu()

        for box, score, label in zip(boxes, scores, labels):
            x1, y1, x2, y2 = box.tolist()
            w = x2 - x1
            h = y2 - y1

            if w <= 0 or h <= 0:
                continue

            yolo_class_id = int(label.item())

            rows.append({
                "annotation_id": annotation_id,
                "image_id": image_id,
                "category_id": class_id_to_category_id[yolo_class_id],
                "bbox_x": round(x1, 2),
                "bbox_y": round(y1, 2),
                "bbox_w": round(w, 2),
                "bbox_h": round(h, 2),
                "score": round(float(score.item()), 4),
            })

            annotation_id += 1

    df = pd.DataFrame(
        rows,
        columns=[
            "annotation_id",
            "image_id",
            "category_id",
            "bbox_x",
            "bbox_y",
            "bbox_w",
            "bbox_h",
            "score",
        ],
    )

    output_csv_path = Path(output_csv_path)
    os.makedirs(output_csv_path.parent, exist_ok=True)
    df.to_csv(output_csv_path, index=False)

    print(f"Saved: {output_csv_path}")
    print(f"Rows: {len(df)}")

    return df


# compare_models 추가 예정, loss 계산 방식 모든 아키텍처 완료되면 고칠 예정
