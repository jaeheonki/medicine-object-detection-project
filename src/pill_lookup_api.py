import os
import sys
import uuid
import tempfile
from pathlib import Path

# src 디렉토리를 sys.path에 추가해 pill_lookup을 직접 import할 수 있게 한다
# (src/__init__.py 없이 uvicorn src.api:app 형태로 실행하기 때문)
sys.path.insert(0, str(Path(__file__).parent))

from fastapi import FastAPI, Request, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from dotenv import load_dotenv
from pill_lookup import detect_pills

load_dotenv()

# 모델 경로와 yaml 경로는 .env에서 관리 (환경마다 경로가 다를 수 있으므로 코드에 하드코딩하지 않음)
MODEL_PATH = os.getenv("MODEL_PATH")
YAML_PATH = os.getenv("YAML_PATH")

app = FastAPI(title="Medicine Detection API")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    # try/except 밖에서 터지는 예외도 JSON으로 반환해 디버깅 가능하게
    return JSONResponse(status_code=500, content={"detail": str(exc), "type": type(exc).__name__})


@app.get("/health")
def health():
    """서버 상태 확인용 엔드포인트"""
    return {"status": "ok"}


@app.post("/predict")
async def predict(image: UploadFile = File(...)):
    """
    이미지를 받아 약을 탐지하고 각 약의 정보를 반환한다.

    파이프라인:
    1. 업로드된 이미지를 임시 파일로 저장
    2. YOLO 모델로 약 탐지 → 클래스명 + confidence 추출
    3. 각 약품명을 식약처 API에 조회 → 효능/복용법/주의사항 수집
    4. 임시 파일 삭제 후 JSON 반환

    응답 예시:
    {
      "detected": [
        {
          "name": "놀텍정 10mg",
          "confidence": 96.3,
          "info": {"약품명": "...", "효능": "...", "복용법": "...", "주의사항": "..."}
        }
      ]
    }
    """
    if MODEL_PATH is None or YAML_PATH is None:
        raise HTTPException(status_code=500, detail="MODEL_PATH 또는 YAML_PATH가 설정되지 않았습니다.")

    # 업로드 파일명에서 확장자 추출. 없으면 .jpg로 폴백
    # YOLO는 확장자로 이미지 파일 여부를 판단하므로 반드시 포함해야 함
    suffix = (Path(image.filename).suffix if image.filename else "") or ".jpg"

    # uuid4로 충돌 없는 임시 파일명 생성
    tmp_path = Path(tempfile.gettempdir()) / f"{uuid.uuid4()}{suffix}"

    try:
        tmp_path.write_bytes(await image.read())
        detected = detect_pills(str(tmp_path), MODEL_PATH, YAML_PATH)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # 추론 성공/실패 상관없이 임시 파일 반드시 삭제
        tmp_path.unlink(missing_ok=True)

    return {"detected": detected}
