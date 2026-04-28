import os
import argparse
from pathlib import Path
import requests
from dotenv import load_dotenv
from ultralytics import YOLO
import yaml

# .env 파일에서 API 키 로드
load_dotenv()

API_KEY = os.getenv("MFDS_API_KEY")
BASE_URL = "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"


def get_pill_info(pill_name):
    # 식품의약품안전처 API에 약품명으로 정보 요청
    params = {
        "serviceKey": API_KEY,
        "itemName": pill_name,
        "type": "json",
        "numOfRows": 1,  # 가장 근접한 결과 1개만 조회
    }
    response = requests.get(BASE_URL, params=params)
    response.raise_for_status()

    data = response.json()
    items = data.get("body", {}).get("items", [])

    if not items:
        return None

    # API 응답에서 필요한 정보만 추출, 각 항목 100자로 제한
    item = items[0]
    def truncate(text, limit=100):
        if not text:
            return "정보 없음"
        return text[:limit] + "..." if len(text) > limit else text

    return {
        "약품명": item.get("itemName"),
        "효능": truncate(item.get("efcyQesitm")),
        "복용법": truncate(item.get("useMethodQesitm")),
        "주의사항": truncate(item.get("atpnQesitm")),
        "부작용": truncate(item.get("seQesitm")),
        "보관법": truncate(item.get("depositMethodQesitm")),
    }


def load_class_names(yaml_path):
    # dataset.yaml에서 YOLO 클래스 id → 약품명 리스트 로드
    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data["names"]


def predict_and_lookup(image_path, model_path, yaml_path, score_threshold=0.5):
    class_names = load_class_names(yaml_path)
    model = YOLO(str(model_path))

    # YOLO로 이미지에서 약 탐지
    results = model.predict(source=str(image_path), conf=score_threshold, verbose=False)
    result = results[0]

    if result.boxes is None or len(result.boxes) == 0:
        print("인식된 약이 없습니다.")
        return

    # 같은 약이 여러 번 탐지될 수 있으므로 set으로 중복 제거
    detected_names = set()
    for label in result.boxes.cls.cpu():
        detected_names.add(class_names[int(label.item())])

    print(f"인식된 약: {', '.join(detected_names)}\n")

    # 인식된 약마다 API 조회 후 출력
    for name in detected_names:
        print(f"{'='*50}")
        info = get_pill_info(name)
        if info:
            for key, value in info.items():
                print(f"[{key}]\n{value}\n")
        else:
            print(f"'{name}' 정보를 찾을 수 없습니다.")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="약 이미지에서 약 정보를 조회합니다.")
    parser.add_argument("--image", required=True, help="약 이미지 경로")
    parser.add_argument("--model", required=True, help="YOLO 모델 가중치 경로 (.pt)")
    parser.add_argument("--yaml", required=True, help="dataset.yaml 경로")
    parser.add_argument("--threshold", type=float, default=0.5, help="confidence threshold")
    args = parser.parse_args()

    predict_and_lookup(
        image_path=args.image,
        model_path=args.model,
        yaml_path=args.yaml,
        score_threshold=args.threshold,
    )
