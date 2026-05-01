from pathlib import Path
import copy
import json
import shutil
import time
import yaml
import random
import torch
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import pandas as pd
from PIL import Image
from ultralytics import YOLO
from torchmetrics.detection.mean_ap import MeanAveragePrecision
from torchvision.ops import box_iou

from utils import download_data, extract_extra_data
from annotation_mapping import run_annotation_mapping, fix_annotation_dir
from json_to_txt import json_to_txt, split_yolo_dataset, build_global_class_map
from model_utils import calc_precision_recall


from pathlib import Path


def prepare_data(data_dir, train_ann_dir, merged_ann_dir, yolo_txt_dir, train_images_dir, yolo_dataset_dir, extra_ann_dir=None):
    data_dir = Path(data_dir)
    train_ann_dir = Path(train_ann_dir)
    merged_ann_dir = Path(merged_ann_dir)
    yolo_txt_dir = Path(yolo_txt_dir)
    train_images_dir = Path(train_images_dir)
    yolo_dataset_dir = Path(yolo_dataset_dir)

    if not train_ann_dir.exists():
        download_data(extract_path=str(data_dir))
    else:
        print("데이터가 이미 존재합니다. 다운로드를 건너뜁니다.")

    if extra_ann_dir is not None:
        extra_ann_dir = Path(extra_ann_dir)
        extra_ann_dir.mkdir(parents=True, exist_ok=True)
        train_images_dir.mkdir(parents=True, exist_ok=True)

        extract_extra_data(
            label_out_dir=extra_ann_dir,
            image_out_dir=train_images_dir,
        )

        print("추가 데이터 다운로드 완료")
        print("추가 원본 어노테이션 저장 위치:", extra_ann_dir)
        print("추가 이미지 저장 위치:", train_images_dir)

    if not merged_ann_dir.exists():
        # 원본과 추가 데이터의 category_id를 item_seq 기준으로 통일해
        # 같은 약이 두 데이터셋에서 다른 category_id를 가지는 중복 클래스 문제를 방지한다
        fixed_all_ann_dir = data_dir / "fixed_annotations"
        fixed_all_ann_dir.mkdir(parents=True, exist_ok=True)

        # 원본 어노테이션 fix: category_id → item_seq
        fix_annotation_dir(
            input_dir=train_ann_dir,
            output_dir=fixed_all_ann_dir,
        )
        print("원본 어노테이션 fix 완료:", fixed_all_ann_dir)

        # 추가 어노테이션 fix: category_id → item_seq (같은 폴더에 합침)
        if extra_ann_dir is not None and Path(extra_ann_dir).exists():
            fix_annotation_dir(
                input_dir=Path(extra_ann_dir),
                output_dir=fixed_all_ann_dir,
            )
            print("추가 어노테이션 fix 완료:", fixed_all_ann_dir)

        # item_seq로 통일된 어노테이션만으로 병합 실행
        result = run_annotation_mapping(
            annotation_root_dir=fixed_all_ann_dir,
            output_dir=merged_ann_dir,
        )

        print("파싱 성공:", len(result["parsed_list"]))
        print("파싱 실패:", len(result["failed_files"]))
        print("병합 이미지 수:", len(result["merged_results"]))
    else:
        print("merged_annotations가 이미 존재합니다. 어노테이션 매핑을 건너뜁니다.")

    if not yolo_txt_dir.exists():
        _, class_names = json_to_txt(
            json_dir=str(merged_ann_dir),
            output_dir=str(yolo_txt_dir),
        )
        print("클래스 수:", len(class_names))
        print("클래스 목록:", class_names[:5])
    else:
        print("YOLO_txt가 이미 존재합니다. 변환을 건너뜁니다.")

    if not yolo_dataset_dir.exists():
        split_yolo_dataset(
            image_dir=str(train_images_dir),
            label_dir=str(yolo_txt_dir),
            output_dir=str(yolo_dataset_dir),
        )
    else:
        print("yolo_dataset이 이미 존재합니다. 분할을 건너뜁니다.")


def create_yaml(yaml_path, yolo_dataset_dir, merged_ann_dir):
    yaml_path = Path(yaml_path)
    yolo_dataset_dir = Path(yolo_dataset_dir)
    merged_ann_dir = Path(merged_ann_dir)

    if not yaml_path.exists():
        _, class_names = build_global_class_map(str(merged_ann_dir))
        yaml_data = {
            "path": str(yolo_dataset_dir),
            "train": "images/train",
            "val": "images/val",
            "nc": len(class_names),
            "names": class_names,
        }
        with open(yaml_path, "w", encoding="utf-8") as f:
            yaml.dump(yaml_data, f, allow_unicode=True)
        print("dataset.yaml 생성 완료:", yaml_path)
    else:
        print("dataset.yaml이 이미 존재합니다. 생성을 건너뜁니다.")


def evaluate_yolo(model, val_image_dir, val_label_dir):
    val_image_dir = Path(val_image_dir)
    val_label_dir = Path(val_label_dir)
    image_exts = {".jpg", ".jpeg", ".png", ".bmp"}
    image_files = [f for f in val_image_dir.iterdir() if f.suffix.lower() in image_exts]
    if len(image_files) > 500:
        image_files = random.sample(image_files, 500)

    metric_50 = MeanAveragePrecision(iou_thresholds=[0.50])
    metric_75_95 = MeanAveragePrecision(iou_thresholds=[0.75, 0.80, 0.85, 0.90, 0.95])
    all_preds, all_targets = [], []

    for img_path in image_files:
        results = model(str(img_path), verbose=False)
        result = results[0]
        img_h, img_w = result.orig_shape

        boxes = result.boxes
        if boxes is not None and len(boxes) > 0:
            pred_boxes = boxes.xyxy.cpu()
            pred_scores = boxes.conf.cpu()
            pred_labels = boxes.cls.cpu().long()
        else:
            pred_boxes = torch.zeros((0, 4))
            pred_scores = torch.zeros(0)
            pred_labels = torch.zeros(0, dtype=torch.long)

        label_path = val_label_dir / f"{img_path.stem}.txt"
        gt_boxes, gt_labels = [], []
        if label_path.exists():
            with open(label_path, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 5:
                        cls_id, x_c, y_c, w, h = map(float, parts)
                        x1 = (x_c - w / 2) * img_w
                        y1 = (y_c - h / 2) * img_h
                        x2 = (x_c + w / 2) * img_w
                        y2 = (y_c + h / 2) * img_h
                        gt_boxes.append([x1, y1, x2, y2])
                        gt_labels.append(int(cls_id))

        gt_boxes_t = torch.tensor(gt_boxes, dtype=torch.float32) if gt_boxes else torch.zeros((0, 4))
        gt_labels_t = torch.tensor(gt_labels, dtype=torch.long) if gt_labels else torch.zeros(0, dtype=torch.long)

        all_preds.append({"boxes": pred_boxes, "scores": pred_scores, "labels": pred_labels})
        all_targets.append({"boxes": gt_boxes_t, "labels": gt_labels_t})

    metric_50.update(all_preds, all_targets)
    metric_75_95.update(all_preds, all_targets)
    result_50 = metric_50.compute()
    result_75_95 = metric_75_95.compute()

    map_50 = result_50["map_50"].item()
    map_75_95 = result_75_95["map"].item()

    precision, recall = calc_precision_recall(all_preds, all_targets)
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0

    return map_50, map_75_95, f1


def train(model_name, yaml_path, output_dir, yolo_dataset_dir, epochs=100, batch=-1, optimizer = "AdamW", lr0=0.01, lrf=0.01, imgsz=640, fliplr=0.5, warmup_epochs=3):
    yaml_path = Path(yaml_path)
    output_dir = Path(output_dir)
    val_image_dir = Path(yolo_dataset_dir) / "images" / "val"
    val_label_dir = Path(yolo_dataset_dir) / "labels" / "val"
    custom_history = {"map_50": [], "map_75_95": [], "f1": [], "time": 0.0}
    best_map_75_95 = 0.0
    start_time = time.time()

    def custom_eval_callback(trainer):
        nonlocal best_map_75_95
        tmp_model = YOLO(model_name)
        tmp_model.model = copy.deepcopy(trainer.model)
        tmp_model.model.eval()
        map_50, map_75_95, f1 = evaluate_yolo(tmp_model, val_image_dir, val_label_dir)
        custom_history["map_50"].append(map_50)
        custom_history["map_75_95"].append(map_75_95)
        custom_history["f1"].append(f1)
        print(f"  Custom | mAP@0.5: {map_50:.4f} | mAP@0.75:0.95: {map_75_95:.4f} | F1: {f1:.4f}")

        if map_75_95 > best_map_75_95:
            best_map_75_95 = map_75_95
            last_pt = Path(trainer.save_dir) / "weights" / "last.pt"
            if last_pt.exists():
                shutil.copy(str(last_pt), str(last_pt.parent / "best_map75_95.pt"))
                print(f"  best_map75_95.pt 저장 (mAP@0.75:0.95: {map_75_95:.4f})")

    model = YOLO(model_name)
    model.add_callback("on_fit_epoch_end", custom_eval_callback)
    model.train(
        data=str(yaml_path),
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        optimizer=optimizer,
        lr0=lr0,
        lrf=lrf,
        fliplr=fliplr,
        warmup_epochs=warmup_epochs,
        project=str(output_dir),
        name="train"
    )

    save_dir = Path(model.trainer.save_dir)
    custom_history["time"] = time.time() - start_time

    # on_fit_epoch_end가 epochs+1번 호출되는 경우 마지막 1개 제거
    for key in ["map_50", "map_75_95", "f1"]:
        if len(custom_history[key]) > epochs:
            custom_history[key] = custom_history[key][:epochs]

    stem = Path(model_name).stem
    with open(save_dir / f"{stem}_history.json", "w") as f:
        json.dump(custom_history, f, indent=4)
    print("커스텀 평가 기록 저장 완료")

    return custom_history, save_dir


def plot_history(custom_history, save_dir, model_name):
    save_dir = Path(save_dir)
    results_csv = save_dir / "results.csv"
    df = pd.read_csv(results_csv)
    df.columns = df.columns.str.strip()

    epochs_range = range(1, len(df) + 1)
    _, axes = plt.subplots(1, 3, figsize=(15, 4))

    axes[0].plot(epochs_range, df["train/box_loss"], label="box loss")
    axes[0].plot(epochs_range, df["train/cls_loss"], label="cls loss")
    axes[0].set_title("Train Loss")
    axes[0].set_xlabel("Epoch")
    axes[0].set_ylabel("Loss")
    axes[0].legend()

    axes[1].plot(epochs_range, custom_history["map_50"], label="mAP@0.5")
    axes[1].plot(epochs_range, custom_history["map_75_95"], label="mAP@0.75:0.95")
    axes[1].set_title("Validation mAP")
    axes[1].set_xlabel("Epoch")
    axes[1].set_ylabel("mAP")
    axes[1].legend()

    axes[2].plot(epochs_range, custom_history["f1"], label="F1")
    axes[2].set_title("Validation F1")
    axes[2].set_xlabel("Epoch")
    axes[2].set_ylabel("F1")
    axes[2].legend()

    plt.suptitle(f"{model_name} Training History")
    plt.tight_layout()
    plt.savefig(str(save_dir / "training_history.png"))
    print("시각화 저장 완료:", save_dir / "training_history.png")


def plot_predictions(save_dir, yolo_dataset_dir, model_name, n=5):
    save_dir = Path(save_dir)
    val_image_dir = Path(yolo_dataset_dir) / "images" / "val"
    val_label_dir = Path(yolo_dataset_dir) / "labels" / "val"
    image_exts = {".jpg", ".jpeg", ".png", ".bmp"}
    image_files = [f for f in val_image_dir.iterdir() if f.suffix.lower() in image_exts]

    samples = random.sample(image_files, min(n, len(image_files)))
    weights_dir = save_dir / "weights"
    # mAP@0.75:0.95 기준 베스트 모델 우선 로드, 없으면 YOLO 기본 best.pt 사용
    model_path = weights_dir / "best_map75_95.pt" if (weights_dir / "best_map75_95.pt").exists() else weights_dir / "best.pt"
    best_model = YOLO(str(model_path))

    _, axes = plt.subplots(n, 2, figsize=(12, n * 5))

    for row, img_path in enumerate(samples):
        img = np.array(Image.open(img_path).convert("RGB"))
        img_h, img_w = img.shape[:2]

        results = best_model(str(img_path), verbose=False)
        result = results[0]
        pred_boxes = result.boxes.xyxy.cpu() if result.boxes and len(result.boxes) > 0 else []
        pred_scores = result.boxes.conf.cpu() if result.boxes and len(result.boxes) > 0 else []
        pred_labels = result.boxes.cls.cpu().long() if result.boxes and len(result.boxes) > 0 else []

        label_path = val_label_dir / f"{img_path.stem}.txt"
        gt_boxes, gt_labels = [], []
        if label_path.exists():
            with open(label_path, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 5:
                        cls_id, x_c, y_c, w, h = map(float, parts)
                        gt_boxes.append([
                            (x_c - w / 2) * img_w, (y_c - h / 2) * img_h,
                            (x_c + w / 2) * img_w, (y_c + h / 2) * img_h,
                        ])
                        gt_labels.append(int(cls_id))

        gt_boxes_t = torch.tensor(gt_boxes, dtype=torch.float32) if gt_boxes else torch.zeros((0, 4))
        gt_labels_t = torch.tensor(gt_labels, dtype=torch.long) if gt_labels else torch.zeros(0, dtype=torch.long)

        axes[row, 0].imshow(img)
        for box, score, label in zip(pred_boxes, pred_scores, pred_labels):
            if score < 0.5:
                continue
            x1, y1, x2, y2 = box
            color = "red"
            if len(gt_boxes_t) > 0:
                iou = box_iou(box.unsqueeze(0), gt_boxes_t)[0]
                best_idx = iou.argmax().item()
                if iou[best_idx] >= 0.5 and gt_labels_t[best_idx].item() == label.item():
                    color = "green"
            rect = patches.Rectangle((x1, y1), x2 - x1, y2 - y1, linewidth=2, edgecolor=color, facecolor="none")
            axes[row, 0].add_patch(rect)
            axes[row, 0].text(x1, y1, f"cls:{label.item()} {score:.2f}", color=color, fontsize=7)
        axes[row, 0].set_title("Prediction (green=correct, red=wrong)")
        axes[row, 0].axis("off")

        axes[row, 1].imshow(img)
        for box, label in zip(gt_boxes_t, gt_labels_t):
            x1, y1, x2, y2 = box
            rect = patches.Rectangle((x1, y1), x2 - x1, y2 - y1, linewidth=2, edgecolor="green", facecolor="none")
            axes[row, 1].add_patch(rect)
            axes[row, 1].text(x1, y1, f"cls:{label.item()}", color="green", fontsize=7)
        axes[row, 1].set_title("Ground Truth")
        axes[row, 1].axis("off")

    plt.suptitle(f"{model_name} Predictions")
    plt.tight_layout()
    plt.savefig(str(save_dir / "predictions.png"))
    print("예측 시각화 저장 완료:", save_dir / "predictions.png")


def save_to_drive(save_dir):
    """학습 결과 파일을 구글 드라이브에 복사한다.

    Colab에서 drive.mount('/content/drive') 실행 후 호출할 것.
    저장 경로: /content/drive/MyDrive/medicine_res/
    """
    save_dir = Path(save_dir)
    drive_save_dir = Path("/content/drive/MyDrive/medicine_res")
    project_root = Path("/content/medicine-object-detection-project")

    if not Path("/content/drive").exists():
        print("구글 드라이브가 마운트되어 있지 않습니다.")
        print("  from google.colab import drive; drive.mount('/content/drive')")
        return

    drive_save_dir.mkdir(parents=True, exist_ok=True)

    submission_name = f"{save_dir.parent.name}_{save_dir.name}_submission.csv"
    candidates = [
        save_dir / "weights" / "best_map75_95.pt",
        save_dir / "training_history.png",
        save_dir / "predictions.png",
        save_dir / "confusion_matrix_normalized.png",
        project_root / "submission" / submission_name,
    ]

    for src in candidates:
        if src.exists():
            shutil.copy(str(src), str(drive_save_dir / src.name))
            print(f"  저장: {src.name}")
        else:
            print(f"  없음 (건너뜀): {src.name}")

    print(f"드라이브 저장 완료 → {drive_save_dir}")


def print_summary(custom_history, model_name):
    map_50_list = custom_history["map_50"]
    map_75_95_list = custom_history["map_75_95"]
    f1_list = custom_history["f1"]
    total_time = custom_history["time"]

    best_map_50 = max(map_50_list)
    best_map_75_95 = max(map_75_95_list)
    best_f1 = max(f1_list)

    best_map_50_epoch = map_50_list.index(best_map_50) + 1
    best_map_75_95_epoch = map_75_95_list.index(best_map_75_95) + 1
    best_f1_epoch = f1_list.index(best_f1) + 1

    hours = int(total_time // 3600)
    minutes = int((total_time % 3600) // 60)
    seconds = int(total_time % 60)

    print(f"\n{'='*50}")
    print(f"  {model_name} 학습 결과 요약")
    print(f"{'='*50}")
    print(f"  Best mAP@0.5       : {best_map_50:.4f}  (Epoch {best_map_50_epoch})")
    print(f"  Best mAP@0.75:0.95 : {best_map_75_95:.4f}  (Epoch {best_map_75_95_epoch})")
    print(f"  Best F1 Score      : {best_f1:.4f}  (Epoch {best_f1_epoch})")
    print(f"  총 학습 시간       : {hours}h {minutes}m {seconds}s")
    print(f"{'='*50}\n")
