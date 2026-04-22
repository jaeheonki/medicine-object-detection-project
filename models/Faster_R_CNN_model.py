# =============================================================================
# Faster_R_CNN_model.py
# 알약(Pill) 객체 탐지를 위한 Faster R-CNN 아키텍처 모듈
#
# [파일 구성]
#   1. build_tuned_faster_rcnn: 튜닝된 Faster R-CNN 모델 빌드 함수
#   2. TwoStageFinetuner      : 2단계 파인튜닝 전략 클래스

# =============================================================================
import math
import random
from typing import Dict, List, Tuple

import torch
import torch.nn as nn
import torchvision
import torchvision.transforms as T
import torchvision.transforms.functional as TF
from torchvision.models.detection import FasterRCNN
from torchvision.models.detection.backbone_utils import resnet_fpn_backbone
from torchvision.models.detection.rpn import AnchorGenerator

# -----------------------------------------------------------------------------
# 기본 상수
# -----------------------------------------------------------------------------
DEVICE      = 'cuda' if torch.cuda.is_available() else 'cpu'
NUM_CLASSES = 57  # 알약 56종 + background(index 0)


# =============================================================================
# 1. build_tuned_faster_rcnn
# -----------------------------------------------------------------------------
# 역할: 알약 도메인에 맞게 튜닝된 Faster R-CNN 모델을 생성하여 반환.
#       torchvision 기본값은 일반 객체(자동차·사람) 기준으로 설계되어 있어
#       알약처럼 소형이고 fine-grained인 객체에는 아래 3가지를 개선한다.
#
# 개선 ①  Anchor 크기 재설계
#   - 기본 anchor (32~512px) → (8~128px)로 축소: 알약은 이미지 대비 매우 작음
#   - aspect_ratio: 극단값(0.5, 2.0) 제거 → 원형/타원(0.75, 1.0, 1.33)만 유지
#   - Anchor와 GT box의 IoU가 높아야 RPN이 proposal을 놓치지 않음
#
# 개선 ②  ROI Align sampling_ratio 2 → 4
#   - bilinear interpolation 샘플 수 증가 → 곡선 경계 알약의 feature 추출 정밀도 향상
#   - 연산량 증가는 전체의 ~5%로 미미
#
# 개선 ③  ResNet-101 + FPN 백본
#   - ResNet-50 대비 더 깊은 레이어 → 각인 문자 같은 texture-level feature 추출력 향상
#   - FPN P2 레벨(고해상도)에서 소형 알약 처리 → Small Object 탐지에 구조적으로 유리
#   - trainable_layers=4: 더 많은 레이어가 알약 도메인에 적응
# =============================================================================

def build_tuned_faster_rcnn(num_classes: int = NUM_CLASSES) -> FasterRCNN:
    """
    알약 특화 튜닝이 적용된 Faster R-CNN 모델을 빌드하여 반환한다.

    Args:
        num_classes (int): 탐지 클래스 수 (background 포함). 기본값 101 (알약 100종 + bg)

    Returns:
        FasterRCNN: 튜닝된 Faster R-CNN 모델 인스턴스
    """

    # ── Backbone: ResNet-101 + FPN ──────────────────────────────────
    # ResNet-101: 깊은 레이어로 각인/색상 등 fine-grained feature 추출력 향상
    # FPN: P2~P6 다중 스케일 feature pyramid → 소형 알약은 P2(고해상도)에서 처리
    # trainable_layers=4: 기존 3 → 증가하여 더 많은 레이어가 도메인에 적응
    backbone = resnet_fpn_backbone(
        backbone_name='resnet101',
        weights='ResNet101_Weights.IMAGENET1K_V1',
        trainable_layers=4,
    )

    # ──  RPN Anchor 크기 재설계 ──────────────────────────────────────
    # sizes: 기본(32~512) → (8~128)로 축소 (FPN 5레벨 각각에 1개 크기 할당)
    # aspect_ratios: 극단값 제거 → 알약 형태(원형·타원)에 맞는 비율만 유지
    # → Anchor-GT IoU 향상으로 RPN이 작은 알약 proposal을 놓치지 않음
    anchor_generator = AnchorGenerator(
        sizes=((8,), (16,), (32,), (64,), (128,)),
        aspect_ratios=((0.75, 1.0, 1.33),) * 5
    )

    # ──  ROI Align sampling_ratio 2 → 4 ──────────────────────────────
    # MultiScaleRoIAlign: FPN의 4개 feature map에서 각 proposal을 7×7로 추출
    # sampling_ratio=4: bilinear interpolation 정밀도 향상
    #   → 곡선 경계를 가진 알약의 feature 추출 품질 개선 (약 1~2% mAP 향상)
    roi_pooler = torchvision.ops.MultiScaleRoIAlign(
        featmap_names=['0', '1', '2', '3'],
        output_size=7,
        sampling_ratio=4
    )

    # ── 모델 조립 ─────────────────────────────────────────────────────────────
    # rpn_pre_nms_top_n_train=3000: 기존 2000 → 증가로 작은 객체 recall 확보
    # box_nms_thresh=0.4: 낮춰서 붙어있는 알약 개별 탐지 가능
    # box_score_thresh=0.05: 낮게 설정하여 초기 학습 시 recall 확보
    model = FasterRCNN(
        backbone=backbone,
        num_classes=num_classes,
        rpn_anchor_generator=anchor_generator,
        box_roi_pool=roi_pooler,
        rpn_pre_nms_top_n_train=3000,
        rpn_pre_nms_top_n_test=1000,
        rpn_post_nms_top_n_train=2000,
        rpn_post_nms_top_n_test=300,
        rpn_nms_thresh=0.7,
        rpn_fg_iou_thresh=0.6,   # Anchor 재설계(소형)와 연동된 foreground 기준
        rpn_bg_iou_thresh=0.3,
        box_score_thresh=0.05,
        box_nms_thresh=0.4,      # 낮춤 → 붙어있는 알약도 개별 탐지
        box_detections_per_img=200,
    )
    return model


# =============================================================================
# 2. TwoStageFinetuner
# -----------------------------------------------------------------------------
# 역할: 소량의 알약 데이터에서 과적합 없이 pretrained 모델을 도메인에 적응시키는
#       2단계 파인튜닝 전략을 관리하는 클래스.
#
# 배경:
#   알약 데이터셋이 클래스당 데이터 수가 3개인 것도 있고 좀 적다.
#   처음부터 전체 모델을 학습하면 ImageNet pretrained feature가 빠르게 손상되고
#   과적합이 발생한다.
#
# Stage 1 (Warm-up, 권장 5~10 epoch, lr=1e-3):
#   - Backbone 전체를 freeze, RPN + Box Head만 학습
#   - Head가 먼저 수렴하여 안정적인 proposal 생성
#
# Stage 2 (Fine-tuning, 권장 20~30 epoch, lr=1e-4):
#   - layer3, layer4, FPN만 unfreeze → 점진적 도메인 적응
#   - Backbone과 Head에 다른 lr 적용 (backbone: lr/10)
#     → pretrained feature 보존하면서 알약 특화 표현 학습
# =============================================================================

class TwoStageFinetuner:
    """
    Faster R-CNN 2단계 파인튜닝 전략 관리 클래스.

    Args:
        model (FasterRCNN): build_tuned_faster_rcnn()으로 생성된 모델

    Methods:
        stage1_freeze_backbone()     : Stage 1 설정 (backbone freeze)
        stage2_unfreeze_partial()    : Stage 2 설정 (layer3/4/FPN unfreeze)
        get_optimizer_stage1(lr)     : Stage 1용 단일 lr optimizer 반환
        get_optimizer_stage2(lr)     : Stage 2용 레이어별 lr optimizer 반환
    """

    def __init__(self, model: FasterRCNN):
        self.model = model

    def stage1_freeze_backbone(self) -> FasterRCNN:
        """
        [Stage 1] Backbone 전체 freeze, RPN + Box Head만 학습.

        목적: pretrained backbone을 보존하면서 detection head가 먼저 수렴하도록 함.
              소량 데이터에서 backbone까지 동시에 학습하면 pretrained feature가 손상됨.

        권장: 5~10 epoch, lr=1e-3
        """
        # Backbone 파라미터 전체 동결
        for param in self.model.backbone.parameters():
            param.requires_grad = False

        trainable = sum(p.numel() for p in self.model.parameters() if p.requires_grad)
        total     = sum(p.numel() for p in self.model.parameters())
        print(f"[Stage 1] 학습 대상: RPN + Box Head (Backbone frozen)")
        print(f"[Stage 1] Trainable: {trainable:,} / {total:,} ({100 * trainable / total:.1f}%)")
        return self.model

    def stage2_unfreeze_partial(
        self,
        layers: List[str] = None
    ) -> FasterRCNN:
        """
        [Stage 2] Backbone의 layer3, layer4, FPN만 unfreeze하여 도메인 적응.

        목적: 깊은 레이어(layer3/4)는 texture·shape 등 고수준 feature를 담당.
              이 레이어만 unfreeze하여 알약 특화 feature를 점진적으로 학습.
              layer1/2(저수준 edge·texture)는 계속 freeze하여 ImageNet feature 보존.

        권장: 20~30 epoch, lr=1e-4

        Args:
            layers (List[str]): unfreeze할 레이어 이름 목록.
                                기본값 ['layer3', 'layer4', 'fpn']
        """
        if layers is None:
            layers = ['layer3', 'layer4', 'fpn']

        # 우선 전체 backbone freeze 후 지정 레이어만 unfreeze
        for param in self.model.backbone.parameters():
            param.requires_grad = False
        for name, param in self.model.backbone.named_parameters():
            if any(layer in name for layer in layers):
                param.requires_grad = True

        trainable = sum(p.numel() for p in self.model.parameters() if p.requires_grad)
        total     = sum(p.numel() for p in self.model.parameters())
        print(f"[Stage 2] Unfrozen backbone layers: {layers}")
        print(f"[Stage 2] Trainable: {trainable:,} / {total:,} ({100 * trainable / total:.1f}%)")
        return self.model

    def get_optimizer_stage1(self, lr: float = 1e-3) -> torch.optim.SGD:
        """
        Stage 1용 optimizer 반환.
        학습 가능한 파라미터(Head)에 단일 lr 적용.

        Args:
            lr (float): 학습률. 권장 1e-3
        Returns:
            SGD optimizer
        """
        params = [p for p in self.model.parameters() if p.requires_grad]
        return torch.optim.SGD(params, lr=lr, momentum=0.9, weight_decay=1e-4)

    def get_optimizer_stage2(self, lr: float = 1e-4) -> torch.optim.SGD:
        """
        Stage 2용 optimizer 반환.
        Backbone과 Head에 서로 다른 lr 적용하여 pretrained feature 보존.
          - backbone: lr * 0.1  → pretrained weight이므로 작은 lr로 세밀하게 조정
          - head    : lr        → 도메인 적응이 필요하므로 full lr 적용

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
            weight_decay=1e-4
        )


# =============================================================================
# 동작 확인 (직접 실행 시에만)
# =============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("Faster R-CNN 모델 동작 확인")
    print("=" * 60)

    # ── Augmentation 확인 ──
    aug          = PillAugmentation(train=True)
    dummy_img    = torch.rand(3, 300, 300)
    dummy_target = {"boxes": torch.tensor([[50., 50., 150., 150.]]), "labels": torch.tensor([1])}
    out_img, out_target = aug(dummy_img, dummy_target)
    print(f"[Augmentation] image: {out_img.shape}, boxes: {out_target['boxes'].shape}")

    # ── 모델 빌드 확인 ──
    model = build_tuned_faster_rcnn(NUM_CLASSES).to(DEVICE)
    total = sum(p.numel() for p in model.parameters())
    print(f"[Model] 총 파라미터: {total:,}")

    # ── Eval Forward Pass ──
    model.eval()
    dummy_images = [torch.rand(3, 600, 600).to(DEVICE)]
    with torch.no_grad():
        preds = model(dummy_images)
    print(f"[Eval]  boxes: {preds[0]['boxes'].shape}, scores: {preds[0]['scores'].shape}")

    # ── Train Loss 확인 ──
    model.train()
    targets = [{"boxes": torch.tensor([[100., 100., 300., 300.]]).to(DEVICE),
                "labels": torch.tensor([1]).to(DEVICE)}]
    with torch.no_grad():
        loss_dict = model(dummy_images, targets)
    print(f"[Train] Loss keys: {list(loss_dict.keys())}")
    print(f"[Train] Total loss: {sum(v for v in loss_dict.values()).item():.4f}")

    # ── Two-stage Fine-tuning 확인 ──
    finetuner = TwoStageFinetuner(model)
    print("=" * 60)
    finetuner.stage1_freeze_backbone()
    print("=" * 60)
    finetuner.stage2_unfreeze_partial()
