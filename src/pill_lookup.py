import os
import re
import argparse
import xml.etree.ElementTree as ET
import requests
from dotenv import load_dotenv
from ultralytics import YOLO
import yaml

# .env 파일에서 API 키 로드
load_dotenv()

API_KEY = os.getenv("MFDS_API_KEY")
# 전문/일반의약품 모두 포함하는 의약품 제품허가정보 API
BASE_URL = "https://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"


def parse_xml_text(xml_str, limit=100):
    # 효능/용법/주의사항 필드는 XML 형식으로 오므로 텍스트만 추출
    if not xml_str:
        return "정보 없음"
    try:
        root = ET.fromstring(xml_str)
        texts = [elem.text.strip() for elem in root.iter() if elem.text and elem.text.strip()]
        text = " ".join(texts)
        return text[:limit] + "..." if len(text) > limit else text
    except ET.ParseError:
        return "정보 없음"


DOSAGE_PATTERN = re.compile(r"\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\b", re.IGNORECASE)
UNIT_KO = {"mg": "밀리그램", "mcg": "마이크로그램", "g": "그램", "ml": "밀리리터"}


def _dosage_to_korean(match):
    number = match.group(1)
    unit = match.group(2).lower()
    return number + UNIT_KO.get(unit, unit)


def _query_api(name):
    params = {
        "serviceKey": API_KEY,
        "item_name": name,
        "type": "json",
        "numOfRows": 1,
    }
    response = requests.get(BASE_URL, params=params)
    response.raise_for_status()
    return response.json().get("body", {}).get("items", [])


def get_pill_info(pill_name):
    # 식품의약품안전처 제품허가정보 API에 약품명으로 정보 요청
    # "놀텍정 10mg"처럼 용량이 붙은 경우 한글로 변환("놀텍정10밀리그램")하여 검색
    search_name = DOSAGE_PATTERN.sub(_dosage_to_korean, pill_name)
    items = _query_api(search_name)

    if not items:
        return None

    # API 응답에서 필요한 정보 추출 (효능/용법/주의사항은 XML → 텍스트 변환)
    item = items[0]
    return {
        "약품명": item.get("ITEM_NAME"),
        "효능": parse_xml_text(item.get("EE_DOC_DATA")),
        "복용법": parse_xml_text(item.get("UD_DOC_DATA")),
        "주의사항": parse_xml_text(item.get("NB_DOC_DATA")),
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

    # 같은 약이 여러 번 탐지될 수 있으므로 최대 confidence만 저장
    detected = {}
    for label, conf in zip(result.boxes.cls.cpu(), result.boxes.conf.cpu()):
        name = class_names[int(label.item())]
        detected[name] = max(detected.get(name, 0.0), float(conf.item()))

    print(f"인식된 약: {', '.join(detected.keys())}\n")

    # 인식된 약마다 API 조회 후 출력
    for name, conf in detected.items():
        print(f"{'='*50}")
        print(f"[신뢰도] {conf * 100:.1f}%\n")
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
