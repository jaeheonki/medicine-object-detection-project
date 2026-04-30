import os
import re
import html
import base64
import io
import argparse
import xml.etree.ElementTree as ET
import requests
from dotenv import load_dotenv
from ultralytics import YOLO
from PIL import Image
import yaml

load_dotenv()

API_KEY = os.getenv("MFDS_API_KEY")
EYAK_API_KEY = os.getenv("EYAK_API_KEY")

# 전문/일반의약품을 모두 포함하는 식품의약품안전처 제품허가정보 API (1차)
BASE_URL = "https://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService07/getDrugPrdtPrmsnDtlInq06"

# e약은요 API — 1차 조회 실패 시 폴백 (2차)
EYAK_BASE_URL = "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"


def parse_xml_text(xml_str):
    """
    API 응답의 효능/용법/주의사항 필드는 XML 문자열로 오기 때문에
    태그를 제거하고 순수 텍스트만 추출한다.

    ElementTree로 파싱 후 text/tail을 모두 수집하고,
    파싱 실패 시 원문에서 정규식으로 태그를 제거하는 방식으로 폴백한다.
    """
    if not xml_str:
        return "정보 없음"
    try:
        root = ET.fromstring(xml_str)
        parts = []
        for elem in root.iter():
            # elem.text: 태그 내부 텍스트, elem.tail: 닫힌 태그 뒤 텍스트
            if elem.text and elem.text.strip():
                parts.append(elem.text.strip())
            if elem.tail and elem.tail.strip():
                parts.append(elem.tail.strip())
        text = " ".join(parts)
    except ET.ParseError:
        # XML 파싱 실패 시 원문에서 태그를 직접 제거
        text = xml_str

    # XML/HTML 태그 제거 (파싱 후 남은 태그 포함)
    text = re.sub(r"<[^>]+>", "", text)
    # &amp;, &nbsp; 등 HTML 엔티티 정리
    text = html.unescape(text)
    text = text.replace("\xa0", " ")  # non-breaking space → 일반 공백
    text = " ".join(text.split())     # 연속 공백 정리

    return text or "정보 없음"


# API DB에서 약품명은 "놀텍정10밀리그램"처럼 용량을 한글로 표기하므로
# YOLO 클래스명("놀텍정 10mg")을 검색 전에 변환해야 한다
DOSAGE_PATTERN = re.compile(r"\s*(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\b", re.IGNORECASE)
UNIT_KO = {"mg": "밀리그램", "mcg": "마이크로그램", "g": "그램", "ml": "밀리리터"}


def _dosage_to_korean(match):
    """정규식 매치 결과에서 숫자와 단위를 꺼내 한글로 조합. 예: ' 10mg' → '10밀리그램'"""
    number = match.group(1)
    unit = match.group(2).lower()
    return number + UNIT_KO.get(unit, unit)


def _query_api(name):
    """식약처 API에 약품명으로 단건 조회 요청. 결과 items 리스트를 반환한다."""
    params = {
        "serviceKey": API_KEY,
        "item_name": name,
        "type": "json",
        "numOfRows": 1,
    }
    response = requests.get(BASE_URL, params=params, timeout=10)
    response.raise_for_status()
    return response.json().get("body", {}).get("items", [])


def _query_eyak_api(name):
    """e약은요 API에 약품명으로 단건 조회 요청. 결과 items 리스트를 반환한다."""
    params = {
        "serviceKey": EYAK_API_KEY,
        "itemName": name,
        "type": "json",
        "numOfRows": 1,
    }
    response = requests.get(EYAK_BASE_URL, params=params, timeout=10)
    response.raise_for_status()
    return response.json().get("body", {}).get("items", [])


def get_pill_info(pill_name):
    """
    약품명으로 약 정보를 조회한다.

    1차: 식약처 제품허가정보 API (전문/일반의약품 모두 포함)
    2차: e약은요 API로 "정보 없음"인 필드만 보완

    YOLO 클래스명의 영문 용량('10mg')은 한글('10밀리그램')로 변환 후 검색한다.
    """
    search_name = DOSAGE_PATTERN.sub(_dosage_to_korean, pill_name)

    info = {"약품명": None, "효능": "정보 없음", "복용법": "정보 없음", "주의사항": "정보 없음", "이미지": None}

    # 1차: 식약처 제품허가정보 API
    items = _query_api(search_name)
    if items:
        item = items[0]
        info["약품명"] = item.get("ITEM_NAME")
        info["효능"] = parse_xml_text(item.get("EE_DOC_DATA"))
        info["복용법"] = parse_xml_text(item.get("UD_DOC_DATA"))
        info["주의사항"] = parse_xml_text(item.get("NB_DOC_DATA"))

    # 2차: "정보 없음"인 필드가 있거나 이미지가 없으면 e약은요 API로 보완
    missing = [k for k in ["효능", "복용법", "주의사항"] if info[k] == "정보 없음"]
    if EYAK_API_KEY and (missing or info["이미지"] is None):
        for query in [search_name, pill_name]:
            eyak_items = _query_eyak_api(query)
            if eyak_items:
                eyak_item = eyak_items[0]
                if info["약품명"] is None:
                    info["약품명"] = eyak_item.get("itemName")
                if info["효능"] == "정보 없음":
                    info["효능"] = eyak_item.get("efcyQesitm") or "정보 없음"
                if info["복용법"] == "정보 없음":
                    info["복용법"] = eyak_item.get("useMethodQesitm") or "정보 없음"
                if info["주의사항"] == "정보 없음":
                    info["주의사항"] = eyak_item.get("atpnQesitm") or "정보 없음"
                info["이미지"] = eyak_item.get("itemImage")
                break

    return info if info["약품명"] is not None else None


def load_class_names(yaml_path):
    """dataset.yaml의 'names' 키에서 YOLO 클래스 인덱스 → 약품명 리스트를 로드한다."""
    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data["names"]


def detect_pills(image_path, model_path, yaml_path, score_threshold=0.5):
    """
    이미지에서 약을 탐지하고 각 약의 API 정보를 함께 반환한다. (FastAPI용)

    같은 약이 이미지 내 여러 위치에서 탐지될 수 있으므로,
    동일 클래스 중 confidence가 가장 높은 박스 하나만 대표값으로 사용한다.

    반환 형태:
    [{"name": "놀텍정 10mg", "confidence": 96.3, "crop_image": "<base64>", "info": {...}}, ...]
    """
    class_names = load_class_names(yaml_path)
    model = YOLO(str(model_path))

    results = model.predict(source=str(image_path), conf=score_threshold, verbose=False)
    result = results[0]

    if result.boxes is None or len(result.boxes) == 0:
        return []

    # 클래스별로 confidence가 가장 높은 박스 하나만 선택
    detected = {}  # name → (conf, bbox_xyxy)
    for label, conf, box in zip(result.boxes.cls.cpu(), result.boxes.conf.cpu(), result.boxes.xyxy.cpu()):
        name = class_names[int(label.item())]
        conf_val = float(conf.item())
        if name not in detected or conf_val > detected[name][0]:
            detected[name] = (conf_val, box.tolist())

    # bbox 영역을 잘라 base64로 인코딩 — Flutter에서 이미지로 바로 표시
    img = Image.open(image_path)

    output = []
    for name, (conf, bbox) in detected.items():
        x1, y1, x2, y2 = [int(v) for v in bbox]
        crop = img.crop((x1, y1, x2, y2))
        buf = io.BytesIO()
        crop.save(buf, format="JPEG")
        crop_b64 = base64.b64encode(buf.getvalue()).decode()

        output.append({
            "name": name,
            "confidence": round(conf * 100, 1),
            "crop_image": crop_b64,
            "info": get_pill_info(name),
        })
    return output


def predict_and_lookup(image_path, model_path, yaml_path, score_threshold=0.5):
    """CLI에서 직접 실행할 때 사용. 탐지 결과를 터미널에 출력한다."""
    class_names = load_class_names(yaml_path)
    model = YOLO(str(model_path))

    results = model.predict(source=str(image_path), conf=score_threshold, verbose=False)
    result = results[0]

    if result.boxes is None or len(result.boxes) == 0:
        print("인식된 약이 없습니다.")
        return

    # 클래스별 최대 confidence 저장
    detected = {}
    for label, conf in zip(result.boxes.cls.cpu(), result.boxes.conf.cpu()):
        name = class_names[int(label.item())]
        detected[name] = max(detected.get(name, 0.0), float(conf.item()))

    print(f"인식된 약: {', '.join(detected.keys())}\n")

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