# =============================================================================
# ssd_model.py
# 알약(Pill) 객체 탐지를 위한 SSD 아키텍처 모듈
#
# [파일 구성]

#   1. ResNetSSDBackbone               : SSD용 ResNet-50 Backbone 클래스
#   2. build_tuned_ssd                 : 튜닝된 SSD 모델 빌드 함수
#   3. SSDTwoStageFinetuner            : SSD 2단계 파인튜닝 전략 클래스
#

# =============================================================================
import collections
import math
import random
from typing import Dict, List, Tuple

import torch
import torch.nn as nn
import torchvision
import torchvision.transforms as T
import torchvision.transforms.functional as TF
from torchvision.models.detection.anchor_utils import DefaultBoxGenerator
from torchvision.models.detection.ssd import SSD, SSDHead

# -----------------------------------------------------------------------------
# 기본 상수
# -----------------------------------------------------------------------------
DEVICE      = 'cuda' if torch.cuda.is_available() else 'cpu'
NUM_CLASSES = 57 # 알약 56종 + background(index 0)


# =============================================================================
# 1. ResNetSSDBackbone
# -----------------------------------------------------------------------------
# 역할: SSD 아키텍처에서 사용할 ResNet-50 기반 feature extractor.
#       원본 SSD의 VGG16 backbone을 대체하여 성능과 효율을 개선한다.
#
# 개선 ③ VGG16 → ResNet-50 교체 이유:
#   - 파라미터 효율 5배 이상: ResNet-50(25M) vs VGG16(138M)
#   - BatchNormalization 내장: 학습 안정성 및 수렴 속도 향상
#   - Residual connection: gradient 소실 방지 → 깊은 feature 추출 가능
#
# 6개 feature map 출력 구조 (300×300 입력 기준):
#   f1: layer2 출력, ~75×75 (stride 4)  ← 매우 작은 알약 탐지
#   f2: layer3 출력, ~38×38 (stride 8)
#   f3: layer4 출력, ~19×19 (stride 16)
#   f4: extra layer 1, ~10×10 (stride 32) ← SSD 추가 레이어
#   f5: extra layer 2, ~5×5
#   f6: extra layer 3, ~3×3              ← 가장 작은 feature map
#
# 개선 ③ extra_layers에 BatchNorm 추가:
#   원본 SSD extra conv layers에는 BN 없음 → 추가로 학습 안정화 및 수렴 속도 향상
# =============================================================================

class ResNetSSDBackbone(nn.Module):
    """
    SSD용 ResNet-50 Backbone. 6개의 feature map을 OrderedDict로 출력한다.

    Args:
        trainable_layers (int): unfreeze할 ResNet 레이어 수 (0~5, 기본값 4)
                                높을수록 더 많은 레이어가 학습됨
    Attributes:
        out_channels (List[int]): 각 feature map의 채널 수
                                  SSDHead 생성 시 in_channels로 전달
    """

    def __init__(self, trainable_layers: int = 4):
        super().__init__()

        # ── ResNet-50 로드 및 레이어 분리 ─────────────────────────────────────
        # BN 내장으로 학습 안정성 확보, Residual connection으로 깊은 feature 추출
        resnet       = torchvision.models.resnet50(weights='ResNet50_Weights.IMAGENET1K_V1')
        self.layer0  = nn.Sequential(resnet.conv1, resnet.bn1, resnet.relu, resnet.maxpool)
        self.layer1  = resnet.layer1   # 출력 채널: 256
        self.layer2  = resnet.layer2   # 출력 채널: 512  → SSD feature map 1 (f1)
        self.layer3  = resnet.layer3   # 출력 채널: 1024 → SSD feature map 2 (f2)
        self.layer4  = resnet.layer4   # 출력 채널: 2048 → SSD feature map 3 (f3)

        # ── Two-stage fine-tuning 초기 설정 ──────────────────────────────────
        # trainable_layers만큼 깊은 레이어부터 unfreeze (layer4가 가장 먼저)
        self._freeze_layers(trainable_layers)

        # ── [개선 ③] SSD 추가 feature map 레이어 (BN 포함) ───────────────────
        # VGG 기반 SSD의 conv6~conv11에 해당하는 역할
        # BatchNorm 추가: 원본 SSD에는 없던 BN → 새 레이어 학습 안정화
        self.extra_layers = nn.ModuleList([
            nn.Sequential(  # f4: 2048ch → 1024ch, ~10×10
                nn.Conv2d(2048, 512,  1), nn.BatchNorm2d(512),  nn.ReLU(inplace=True),
                nn.Conv2d(512,  1024, 3, stride=2, padding=1), nn.BatchNorm2d(1024), nn.ReLU(inplace=True),
            ),
            nn.Sequential(  # f5: 1024ch → 512ch, ~5×5
                nn.Conv2d(1024, 256, 1), nn.BatchNorm2d(256), nn.ReLU(inplace=True),
                nn.Conv2d(256,  512, 3, stride=2, padding=1), nn.BatchNorm2d(512), nn.ReLU(inplace=True),
            ),
            nn.Sequential(  # f6: 512ch → 256ch, ~3×3
                nn.Conv2d(512, 128, 1), nn.BatchNorm2d(128), nn.ReLU(inplace=True),
                nn.Conv2d(128, 256, 3, stride=2, padding=1), nn.BatchNorm2d(256), nn.ReLU(inplace=True),
            ),
        ])

        # SSDHead 생성 시 in_channels로 전달되는 각 feature map 채널 수
        self.out_channels = [512, 1024, 2048, 1024, 512, 256]

    def _freeze_layers(self, trainable_layers: int) -> None:
        """
        ResNet 레이어를 뒤(깊은 레이어)에서부터 trainable_layers개만 unfreeze.
        예: trainable_layers=4이면 layer1~layer4 중 layer1은 freeze, 나머지 unfreeze.
        """
        layers       = [self.layer0, self.layer1, self.layer2, self.layer3, self.layer4]
        freeze_up_to = len(layers) - trainable_layers
        for i, layer in enumerate(layers):
            if i < freeze_up_to:
                for param in layer.parameters():
                    param.requires_grad = False

    def forward(self, x: torch.Tensor) -> collections.OrderedDict:
        """
        6개의 feature map을 OrderedDict로 반환.
        SSD 내부에서 "0"~"5" 키로 접근.
        """
        x  = self.layer0(x)
        x  = self.layer1(x)
        f1 = self.layer2(x)    # ~75×75, 512ch
        f2 = self.layer3(f1)   # ~38×38, 1024ch
        f3 = self.layer4(f2)   # ~19×19, 2048ch
        f4 = self.extra_layers[0](f3)  # ~10×10, 1024ch
        f5 = self.extra_layers[1](f4)  # ~5×5,   512ch
        f6 = self.extra_layers[2](f5)  # ~3×3,   256ch

        out = collections.OrderedDict()
        out["0"] = f1
        out["1"] = f2
        out["2"] = f3
        out["3"] = f4
        out["4"] = f5
        out["5"] = f6
        return out


# =============================================================================
# 2. build_tuned_ssd
# -----------------------------------------------------------------------------
# 역할: 알약 도메인에 최적화된 SSD 모델을 조립하여 반환.
#       ResNetSSDBackbone + 재설계된 DefaultBoxGenerator + SSDHead를 결합.
#
# 개선 ① Default Box 크기 재설계:
#   - scales 시작값: 0.07(기본) → 0.04 (300×300 기준 12px)로 축소
#     → 기본값은 일반 객체 기준 ~21px부터 시작, 작은 알약은 이보다 더 작음
#   - aspect_ratios: [2, 3] 제거 → 원형/타원(0.75, 1.0, 1.33)만 유지
#     → 불필요한 anchor 수 감소 → NMS 연산량 감소 + 학습 안정화
#   - 고해상도 f1(소형 알약)과 저해상도 f6(여러 알약 묶음)에는 원형만 적용
# =============================================================================

def build_tuned_ssd(
    num_classes: int = NUM_CLASSES,
    input_size: int  = 300
) -> SSD:
    """
    알약 특화 튜닝이 적용된 SSD 모델을 빌드하여 반환한다.

    Args:
        num_classes (int): 탐지 클래스 수 (background 포함). 기본값 101
        input_size  (int): 모델 입력 해상도. 기본값 300 (SSD300)
    Returns:
        SSD: 튜닝된 SSD 모델 인스턴스
    """
    backbone = ResNetSSDBackbone(trainable_layers=4)

    # ── [개선 ①] Default Box 재설계 ──────────────────────────────────────────
    # scales: 0.04부터 시작 → 소형 알약(12px~)까지 커버
    # aspect_ratios: feature map 레벨별로 알약 형태에 맞게 설계
    #   f1(고해상도, 소형 알약): 원형[1.0]만
    #   f2~f4(중간): 원형+타원[0.75, 1.0, 1.33]
    #   f5~f6(저해상도, 알약 묶음): 원형[1.0]만
    # steps: 각 feature map의 stride에 맞게 설정 (default box 간격 조절)
    anchor_generator = DefaultBoxGenerator(
        aspect_ratios=[
            [1.0],              # f1 ~75×75: 소형 원형 알약 전용
            [0.75, 1.0, 1.33],  # f2 ~38×38: 원형 + 타원
            [0.75, 1.0, 1.33],  # f3 ~19×19
            [0.75, 1.0, 1.33],  # f4 ~10×10
            [1.0],              # f5 ~5×5: 단순화
            [1.0],              # f6 ~3×3: 단순화
        ],
        scales=[0.04, 0.10, 0.26, 0.42, 0.58, 0.74, 0.90],
        steps=[4, 8, 16, 32, 64, 100],
        clip=True  # default box가 이미지 경계를 벗어나지 않도록 clamp
    )

    num_anchors = anchor_generator.num_anchors_per_location()

    # ── SSDHead 조립 ─────────────────────────────────────────────────────────
    # 각 feature map 위치에서 Conv 1회로 직접 클래스 + box offset 예측
    # (Faster R-CNN과 달리 RPN + ROI Align 없음 → Single-stage)
    head = SSDHead(
        in_channels=backbone.out_channels,
        num_anchors=num_anchors,
        num_classes=num_classes,
    )

    # ── 최종 SSD 모델 조립 ───────────────────────────────────────────────────
    # score_thresh=0.02: 낮게 설정 → 초기 학습 시 recall 확보
    # nms_thresh=0.4   : 낮춤 → 붙어있는 알약 개별 탐지 가능
    # topk_candidates=400: NMS 이전 후보 수 → 소형 알약 누락 방지
    model = SSD(
        backbone=backbone,
        anchor_generator=anchor_generator,
        size=(input_size, input_size),
        num_classes=num_classes,
        head=head,
        score_thresh=0.02,
        nms_thresh=0.4,
        detections_per_img=200,
        topk_candidates=400,
    )
    return model


# =============================================================================
# 3. SSDTwoStageFinetuner
# -----------------------------------------------------------------------------
# 역할: SSD에 특화된 2단계 파인튜닝 전략을 관리하는 클래스.
#
# Faster R-CNN TwoStageFinetuner와의 차이점:
#   - SSD는 backbone feature map이 직접 prediction에 사용되므로
#     backbone 품질이 최종 성능에 더 민감하게 반응
#   - 따라서 Stage 1을 더 길게(10~15 epoch) 진행하여 head를 완전 수렴 후 Stage 2 전환
#   - extra_layers는 pretrained weight 없는 새 레이어이므로
#     Stage 1에서도 반드시 학습해야 feature map이 올바르게 생성됨
#
# Stage 1 (Warm-up, 권장 10~15 epoch, lr=1e-3):
#   - backbone ResNet freeze, extra_layers + SSDHead만 학습
#   - extra_layers는 새 레이어 → pretrained weight 없음 → Stage1부터 학습 필수
#
# Stage 2 (Fine-tuning, 권장 20~30 epoch, lr=1e-4):
#   - layer3, layer4, extra_layers unfreeze → 점진적 도메인 적응
#   - backbone: lr/10, head: full lr → pretrained feature 보존
# =============================================================================

class SSDTwoStageFinetuner:
    """
    SSD 2단계 파인튜닝 전략 관리 클래스.

    Args:
        model (SSD): build_tuned_ssd()로 생성된 모델

    Methods:
        stage1_freeze_backbone()  : Stage 1 설정 (ResNet freeze, extra_layers 학습)
        stage2_unfreeze_partial() : Stage 2 설정 (layer3/4/extra unfreeze)
        get_optimizer_stage1(lr)  : Stage 1용 단일 lr optimizer 반환
        get_optimizer_stage2(lr)  : Stage 2용 레이어별 lr optimizer 반환
    """

    def __init__(self, model: SSD):
        self.model = model

    def stage1_freeze_backbone(self) -> SSD:
        """
        [Stage 1] backbone ResNet 전체 freeze, extra_layers + SSDHead만 학습.

        extra_layers를 Stage 1부터 학습하는 이유:
          extra_layers는 새로 추가된 레이어로 pretrained weight가 없음.
          이 레이어가 올바른 feature map을 생성해야 head가 정상 작동함.
          backbone을 freeze해도 extra_layers는 반드시 학습해야 함.

        권장: 10~15 epoch (Faster R-CNN보다 길게), lr=1e-3
        """
        # ResNet(layer0~4) 전체 freeze
        for param in self.model.backbone.parameters():
            param.requires_grad = False
        # extra_layers는 새 레이어이므로 Stage 1부터 unfreeze
        for param in self.model.backbone.extra_layers.parameters():
            param.requires_grad = True

        trainable = sum(p.numel() for p in self.model.parameters() if p.requires_grad)
        total     = sum(p.numel() for p in self.model.parameters())
        print(f"[SSD Stage 1] 학습 대상: SSDHead + Extra layers (ResNet frozen)")
        print(f"[SSD Stage 1] Trainable: {trainable:,} / {total:,} ({100 * trainable / total:.1f}%)")
        return self.model

    def stage2_unfreeze_partial(self) -> SSD:
        """
        [Stage 2] layer3, layer4, extra_layers unfreeze → 점진적 도메인 적응.

        layer3/4를 unfreeze하는 이유:
          깊은 레이어(layer3/4)는 texture·각인·색상 등 고수준 feature 담당.
          이 레이어를 알약 도메인에 맞게 fine-tune하여 탐지 정밀도 향상.
          layer0/1(저수준 edge/texture)은 freeze 유지 → ImageNet feature 보존.

        권장: 20~30 epoch, lr=1e-4
        """
        # 우선 전체 backbone freeze
        for param in self.model.backbone.parameters():
            param.requires_grad = False
        # layer3, layer4, extra_layers만 unfreeze
        for name, param in self.model.backbone.named_parameters():
            if any(layer in name for layer in ['layer3', 'layer4', 'extra']):
                param.requires_grad = True
        # SSDHead 전체 학습
        for param in self.model.head.parameters():
            param.requires_grad = True

        trainable = sum(p.numel() for p in self.model.parameters() if p.requires_grad)
        total     = sum(p.numel() for p in self.model.parameters())
        print(f"[SSD Stage 2] Unfrozen: layer3, layer4, extra_layers")
        print(f"[SSD Stage 2] Trainable: {trainable:,} / {total:,} ({100 * trainable / total:.1f}%)")
        return self.model

    def get_optimizer_stage1(self, lr: float = 1e-3) -> torch.optim.SGD:
        """
        Stage 1용 optimizer 반환.
        학습 가능한 파라미터(extra_layers + Head)에 단일 lr 적용.

        Args:
            lr (float): 학습률. 권장 1e-3
        Returns:
            SGD optimizer
        """
        params = [p for p in self.model.parameters() if p.requires_grad]
        return torch.optim.SGD(params, lr=lr, momentum=0.9, weight_decay=5e-4)

    def get_optimizer_stage2(self, lr: float = 1e-4) -> torch.optim.SGD:
        """
        Stage 2용 optimizer 반환.
        Backbone과 Head에 서로 다른 lr 적용하여 pretrained feature 보존.
          - backbone (layer3/4/extra): lr * 0.1
          - head                     : lr (full)

        Args:
            lr (float): Head 기준 학습률. 권장 1e-4. backbone은 자동으로 lr/10 적용.
        Returns:
            SGD optimizer (2개의 param_group)
        """
        bb_params   = [p for n, p in self.model.named_parameters() if 'backbone' in n and p.requires_grad]
        head_params = [p for n, p in self.model.named_parameters() if 'backbone' not in n and p.requires_grad]
        return torch.optim.SGD(
            [
                {'params': bb_params,   'lr': lr * 0.1},  # backbone: pretrained → lr/10
                {'params': head_params, 'lr': lr},         # head: 도메인 적응 → full lr
            ],
            momentum=0.9,
            weight_decay=5e-4
        )


# =============================================================================
# 동작 확인 (직접 실행 시에만)
# =============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("SSD 모델 동작 확인")
    print("=" * 60)

    # ── Backbone feature map 확인 ──
    test_backbone = ResNetSSDBackbone(trainable_layers=4).to(DEVICE)
    dummy         = torch.rand(1, 3, 300, 300).to(DEVICE)
    feature_maps  = test_backbone(dummy)
    print("[Backbone] feature map shapes:")
    for i, fm in enumerate(feature_maps.values()):
        print(f"   f{i + 1}: {tuple(fm.shape)}")

    # ── Augmentation 확인 ──
    aug_ssd      = PillAugmentationSSD(train=True)
    dummy_img    = torch.rand(3, 300, 300)
    dummy_target = {"boxes": torch.tensor([[50., 50., 150., 150.]]), "labels": torch.tensor([1])}
    out_img, out_target = aug_ssd(dummy_img, dummy_target)
    print(f"[Augmentation] image: {out_img.shape}")

    # ── 모델 빌드 확인 ──
    model = build_tuned_ssd(NUM_CLASSES).to(DEVICE)
    total = sum(p.numel() for p in model.parameters())
    print(f"[Model] 총 파라미터: {total:,}")

    # ── Eval Forward Pass ──
    model.eval()
    dummy_images = [torch.rand(3, 300, 300).to(DEVICE)]
    with torch.no_grad():
        preds = model(dummy_images)
    print(f"[Eval]  boxes: {preds[0]['boxes'].shape}, scores: {preds[0]['scores'].shape}")

    # ── Train Loss 확인 ──
    model.train()
    targets = [{"boxes": torch.tensor([[50., 50., 200., 200.]]).to(DEVICE),
                "labels": torch.tensor([1]).to(DEVICE)}]
    with torch.no_grad():
        loss_dict = model(dummy_images, targets)
    print(f"[Train] Loss keys: {list(loss_dict.keys())}")
    print(f"[Train] Total loss: {sum(v for v in loss_dict.values()).item():.4f}")

    # ── Two-stage Fine-tuning 확인 ──
    finetuner = SSDTwoStageFinetuner(model)
    print("=" * 60)
    finetuner.stage1_freeze_backbone()
    print("=" * 60)
    finetuner.stage2_unfreeze_partial()
