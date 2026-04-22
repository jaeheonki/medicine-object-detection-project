import torch
from torch.utils.data import DataLoader, random_split
from torchvision import transforms


# 가장 기본적인 전처리를 해주는 함수, ToTensor와 정규화 작업만 진행
def basic_transform():
    transform = transforms.Compose(
        [
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ]
    )

    return transform


# 가변 데이터 처리를 위함
def collate_fn(batch):
    return tuple(zip(*batch))


# Dataset을 입력으로 넣으면 random_split을 통해 trainset을 train과 valid로 나누는 작업을 진행, 이후 DataLoader를 통해 배치단위를 만듬
# 최종적으로 train_loader와 val_loader를 리턴
def make_dataloaders(dataset, batch_size=32, train_ratio=0.7, val_ratio=0.3, seed=42):
    if abs(train_ratio + val_ratio - 1.0) > 1e-8:
        raise ValueError("train_ratio + val_ratio는 1이어야 합니다.")

    total_size = len(dataset)
    train_size = int(total_size * train_ratio)
    val_size = int(total_size * val_ratio)

    generator = torch.Generator().manual_seed(seed)

    train_dataset, val_dataset = random_split(
        dataset, [train_size, val_size], generator=generator
    )

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=2,
        pin_memory=True,
        collate_fn=collate_fn,
    )

    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=2,
        pin_memory=True,
        collate_fn=collate_fn,
    )
    return train_loader, val_loader
