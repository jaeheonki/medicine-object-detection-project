
import os
import json
from collections import defaultdict

import torch
from PIL import Image
from torch.utils.data import Dataset, DataLoader, random_split
from transformers import DetrImageProcessor


def load_coco_json(json_path):
    with open(json_path, "r", encoding="utf-8") as f:
        coco = json.load(f)

    images = coco["images"]
    annotations = coco["annotations"]
    categories = coco["categories"]

    image_id_to_annotations = defaultdict(list)
    for ann in annotations:
        image_id_to_annotations[ann["image_id"]].append(ann)

    return {
        "images": images,
        "annotations": annotations,
        "categories": categories,
        "image_id_to_annotations": image_id_to_annotations,
    }


class PillDetrDataset(Dataset):
    def __init__(self, json_path, image_dir, processor=None):
        self.data = load_coco_json(json_path)
        self.image_dir = image_dir
        self.processor = processor or DetrImageProcessor.from_pretrained("facebook/detr-resnet-50")

        self.images = self.data["images"]
        self.image_id_to_annotations = self.data["image_id_to_annotations"]
        self.categories = self.data["categories"]

        sorted_ids = sorted(cat["id"] for cat in self.categories)
        self.category_map = {old_id: new_id for new_id, old_id in enumerate(sorted_ids)}

    def __len__(self):
        return len(self.images)

    def __getitem__(self, idx):
        image_info = self.images[idx]
        image_id = image_info["id"]
        file_name = image_info["file_name"]

        image_path = os.path.join(self.image_dir, file_name)
        image = Image.open(image_path).convert("RGB")

        anns = self.image_id_to_annotations.get(image_id, [])

        remapped_anns = []
        for ann in anns:
            category_id = ann["category_id"]
            if category_id not in self.category_map:
                continue

            new_ann = ann.copy()
            new_ann["category_id"] = self.category_map[category_id]
            remapped_anns.append(new_ann)

        target = {
            "image_id": image_id,
            "annotations": remapped_anns,
        }

        encoding = self.processor(
            images=image,
            annotations=target,
            return_tensors="pt"
        )

        pixel_values = encoding["pixel_values"].squeeze(0)
        labels = encoding["labels"][0]

        return pixel_values, labels


def detr_collate_fn(batch):
    images = [item[0] for item in batch]
    targets = [item[1] for item in batch]
    return images, targets


def make_detr_dataloaders(dataset, batch_size=2, train_ratio=0.8, seed=42):
    total_size = len(dataset)
    train_size = int(total_size * train_ratio)
    val_size = total_size - train_size

    generator = torch.Generator().manual_seed(seed)
    train_dataset, val_dataset = random_split(
        dataset, [train_size, val_size], generator=generator
    )

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        collate_fn=detr_collate_fn,
    )

    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        collate_fn=detr_collate_fn,
    )

    return train_loader, val_loader
