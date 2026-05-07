import os
import sys
import uuid
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

import gdown  # type: ignore[import-untyped]

# src 디렉토리를 sys.path에 추가해 pill_lookup을 직접 import할 수 있게 한다
# (src/__init__.py 없이 uvicorn src.pill_lookup_api:app 형태로 실행하기 때문)
sys.path.insert(0, str(Path(__file__).parent))

from fastapi import FastAPI, Request, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from pill_lookup import detect_pills, get_pill_info, load_class_names  # type: ignore[import-not-found]

load_dotenv()

# 모델 경로와 yaml 경로는 .env에서 관리 (환경마다 경로가 다를 수 있으므로 코드에 하드코딩하지 않음)
MODEL_PATH = os.getenv("MODEL_PATH")
YAML_PATH = os.getenv("YAML_PATH")
MODEL_GDRIVE_ID = os.getenv("MODEL_GDRIVE_ID")
YAML_GDRIVE_ID = os.getenv("YAML_GDRIVE_ID")

# checkpoints 폴더는 프로젝트 루트 기준
CHECKPOINTS_DIR = Path(__file__).resolve().parent.parent / "checkpoints"


def _ensure_model_files():
    """서버 시작 시 모델 파일이 없으면 구글 드라이브에서 자동으로 다운로드한다."""
    CHECKPOINTS_DIR.mkdir(exist_ok=True)

    files = [
        (MODEL_GDRIVE_ID, Path(MODEL_PATH) if MODEL_PATH else CHECKPOINTS_DIR / "best_map75_95.pt"),
        (YAML_GDRIVE_ID,  Path(YAML_PATH)  if YAML_PATH  else CHECKPOINTS_DIR / "dataset.yaml"),
    ]

    for gdrive_id, dest in files:
        if dest.exists():
            print(f"[모델 확인] 이미 존재합니다: {dest.name}")
            continue
        if not gdrive_id:
            print(f"[모델 확인] Drive ID 없음, 건너뜀: {dest.name}")
            continue
        print(f"[모델 다운로드] {dest.name} ...")
        gdown.download(id=gdrive_id, output=str(dest), quiet=False)
        print(f"[모델 다운로드] 완료: {dest.name}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 서버 시작 시 모델 파일 존재 여부 확인 후 필요하면 다운로드
    _ensure_model_files()
    yield


app = FastAPI(title="Medicine Detection API", lifespan=lifespan)

# Flutter 웹(localhost:8080)에서 API(localhost:9000)를 호출할 때 브라우저의 CORS 정책에 막히므로
# 모든 origin을 허용하는 미들웨어를 추가한다
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


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
    2. YOLO 모델로 약 탐지 → 클래스명 + confidence + bbox 추출
    3. bbox 영역을 잘라 base64로 인코딩
    4. 각 약품명을 식약처 API에 조회 → 효능/복용법/주의사항 수집
    5. 임시 파일 삭제 후 JSON 반환

    응답 예시:
    {
      "detected": [
        {
          "name": "놀텍정 10mg",
          "confidence": 96.3,
          "crop_image": "<base64>",
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

    # uuid4로 충돌 없는 임시 파일명 생성 (동시 요청 시 파일명 충돌 방지)
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


@app.get("/classes")
def get_classes():
    """dataset.yaml에서 인식 가능한 약품명 리스트를 반환한다."""
    if YAML_PATH is None:
        raise HTTPException(status_code=500, detail="YAML_PATH가 설정되지 않았습니다.")
    return {"classes": load_class_names(YAML_PATH)}


@app.get("/pill-info")
def pill_info(name: str):
    """약품명으로 상세 정보(효능/복용법/주의사항/이미지)를 반환한다."""
    info = get_pill_info(name)
    return {"info": info}
