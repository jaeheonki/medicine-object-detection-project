import os
import json
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import Dataset
import torchvision.transforms.functional as F


class PillDataset(Dataset):
    """
    annotation_mapping.py 출력 포맷 기준 Dataset.
    merged_annotations 폴더의 JSON 파일(이미지 1장당 1개)을 읽어 반환.

    Args:
        ann_dir   : merged_annotations 폴더 경로
        image_dir : 이미지 폴더 경로
        transform : 이미지 전처리 함수 (없으면 ToTensor만 적용)
    """

    def __init__(self, ann_dir, image_dir, transform=None):
        self.image_dir = image_dir
        self.transform = transform
        self.ann_paths = sorted(Path(ann_dir).glob("*.json"))

        # category_id를 0부터 시작하는 연속 정수로 매핑 (torchvision 모델 요구사항)
        raw_ids = set()
        for p in self.ann_paths:
            with open(p, "r", encoding="utf-8") as f:
                item = json.load(f)
            for ann in item.get("merged_annotations", []):
                if ann["bbox_xyxy"] is not None:
                    raw_ids.add(ann["raw_annotation"]["category_id"])
        self.category_map = {raw_id: idx + 1 for idx, raw_id in enumerate(sorted(raw_ids))}

    def __len__(self):
        return len(self.ann_paths)

    def __getitem__(self, idx):
        with open(self.ann_paths[idx], "r", encoding="utf-8") as f:
            item = json.load(f)

        # 이미지 로드
        image = Image.open(os.path.join(self.image_dir, item["file_name"])).convert("RGB")

        if self.transform:
            image = self.transform(image)
        else:
            image = F.to_tensor(image)  # [C, H, W], float32

        # 어노테이션 로드 (bbox_xyxy 사용)
        anns = [a for a in item.get("merged_annotations", []) if a["bbox_xyxy"] is not None]

        if len(anns) == 0:
            boxes  = torch.zeros((0, 4), dtype=torch.float32)
            labels = torch.zeros((0,), dtype=torch.int64)
        else:
            boxes  = torch.tensor([a["bbox_xyxy"] for a in anns], dtype=torch.float32)
            labels = torch.tensor([self.category_map[a["raw_annotation"]["category_id"]] for a in anns], dtype=torch.int64)

        target = {"boxes": boxes, "labels": labels}
        return image, target


class PillTestDataset(Dataset):
    """
    제출용 테스트셋 (정답 없음).
    이미지 폴더에서 직접 읽기.

    Args:
        image_dir : 테스트 이미지 폴더 경로
        transform : 이미지 전처리 함수
    """

    def __init__(self, image_dir, transform=None):
        self.image_dir = image_dir
        self.transform = transform
        exts = {".jpg", ".jpeg", ".png"}
        self.items = [
            {"file_name": p.name, "image_id": i}
            for i, p in enumerate(sorted(Path(image_dir).iterdir()))
            if p.suffix.lower() in exts
        ]

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        info = self.items[idx]
        image = Image.open(os.path.join(self.image_dir, info["file_name"])).convert("RGB")

        if self.transform:
            image = self.transform(image)
        else:
            image = F.to_tensor(image)

        return image, info["image_id"]


def collate_fn(batch):
    """
    객체 탐지용 collate_fn.
    이미지마다 박스 수가 달라서 기본 collate 사용 불가 → 튜플로 묶어 반환.
    """
    return tuple(zip(*batch))
