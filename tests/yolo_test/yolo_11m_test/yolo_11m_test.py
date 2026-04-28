from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.append(str(PROJECT_ROOT / "src"))

from yolo_utils import prepare_data, create_yaml, train, plot_history, plot_predictions, print_summary
from model_utils import make_yolo_submission

DATA_DIR = PROJECT_ROOT / "data"
TRAIN_ANN_DIR = DATA_DIR / "sprint_ai_project1_data" / "train_annotations"
MERGED_ANN_DIR = DATA_DIR / "merged_annotations"
YOLO_TXT_DIR = DATA_DIR / "sprint_ai_project1_data" / "YOLO_txt"
TRAIN_IMAGES_DIR = DATA_DIR / "sprint_ai_project1_data" / "train_images"
YOLO_DATASET_DIR = DATA_DIR / "yolo_dataset"
YAML_PATH = YOLO_DATASET_DIR / "dataset.yaml"
OUTPUT_DIR = PROJECT_ROOT / "outputs" / "yolo_11m"
MODEL_NAME = "yolo11m.pt"


def main():
    prepare_data(DATA_DIR, TRAIN_ANN_DIR, MERGED_ANN_DIR, YOLO_TXT_DIR, TRAIN_IMAGES_DIR, YOLO_DATASET_DIR)
    create_yaml(YAML_PATH, YOLO_DATASET_DIR, MERGED_ANN_DIR)
    custom_history, save_dir = train(MODEL_NAME, YAML_PATH, OUTPUT_DIR, YOLO_DATASET_DIR, epochs=200, optimizer="AdamW", batch=16, lrf=0.1)
    print_summary(custom_history, MODEL_NAME)
    plot_history(custom_history, save_dir, MODEL_NAME)
    plot_predictions(save_dir, YOLO_DATASET_DIR, MODEL_NAME)
    make_yolo_submission(save_dir)


if __name__ == "__main__":
    main()
