"""
구글 드라이브에서 YOLO 모델(.pt)과 데이터셋 설정(.yaml)을 다운로드한다.

사용법:
    python scripts/download_models.py

파일 ID는 .env의 MODEL_GDRIVE_ID / YAML_GDRIVE_ID에서 읽는다.
다운로드 위치는 프로젝트 루트의 checkpoints/ 폴더다.
이미 파일이 존재하면 다운로드를 건너뛴다.
"""

from pathlib import Path
import os
import gdown
from dotenv import load_dotenv

load_dotenv()

CHECKPOINTS_DIR = Path(__file__).resolve().parent.parent / "checkpoints"
CHECKPOINTS_DIR.mkdir(exist_ok=True)

# .env에서 구글 드라이브 파일 ID 읽기
MODEL_GDRIVE_ID = os.getenv("MODEL_GDRIVE_ID")
YAML_GDRIVE_ID = os.getenv("YAML_GDRIVE_ID")

FILES = [
    (MODEL_GDRIVE_ID, CHECKPOINTS_DIR / "best_map75_95.pt"),
    (YAML_GDRIVE_ID,  CHECKPOINTS_DIR / "dataset.yaml"),
]


def download(file_id: str, dest: Path):
    if dest.exists():
        print(f"이미 존재합니다. 건너뜀: {dest.name}")
        return
    print(f"다운로드 중: {dest.name}")
    gdown.download(id=file_id, output=str(dest), quiet=False)
    print(f"완료: {dest.name}")


if __name__ == "__main__":
    if not MODEL_GDRIVE_ID or not YAML_GDRIVE_ID:
        raise RuntimeError(".env에 MODEL_GDRIVE_ID 또는 YAML_GDRIVE_ID가 없습니다.")

    for file_id, dest in FILES:
        download(file_id, dest)
