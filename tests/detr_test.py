import torch
from src.detr_model_utils import (
    prepare_detr_data,
    build_detr_model,
    train_detr,
    plot_predictions_detr,
    print_summary_detr,
    print_summary_from_json,
)
from src.model_utils import plot_history


TRAIN_JSON = "/content/train_split.json"
VAL_JSON = "/content/val_split.json"
IMAGE_DIR = "/content/ai10-level1-project/sprint_ai_project1_data/train_images"

BATCH_SIZE = 4
EPOCHS = 100
LR = 1e-4
WD = 1e-4
MODEL_NAME = "detr"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def main():
    print("DEVICE:", DEVICE)

    train_loader, val_loader, val_dataset, id2label, label2id = prepare_detr_data(
        TRAIN_JSON, VAL_JSON, IMAGE_DIR, BATCH_SIZE
    )
    print("num_classes:", len(id2label))

    model = build_detr_model(id2label, label2id)

    history = train_detr(
        model=model,
        model_name=MODEL_NAME,
        train_loader=train_loader,
        val_loader=val_loader,
        epochs=EPOCHS,
        lr=LR,
        wd=WD,
        eval_threshold=0.5,
    )

    print_summary_detr(history, MODEL_NAME)
    print_summary_from_json(MODEL_NAME)
    plot_history(history, MODEL_NAME)
    plot_predictions_detr(model, val_dataset, MODEL_NAME)


if __name__ == "__main__":
    main()
