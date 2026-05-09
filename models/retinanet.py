import torch
from torchvision.models.detection import retinanet_resnet50_fpn_v2, RetinaNet_ResNet50_FPN_V2_Weights
from torchvision.models.detection.retinanet import RetinaNetHead

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def build_retinanet(num_classes):
    # COCO 사전학습 가중치 로드
    model = retinanet_resnet50_fpn_v2(weights=RetinaNet_ResNet50_FPN_V2_Weights.COCO_V1)

    # 헤드만 num_classes에 맞게 교체
    # torchvision RetinaNet은 배경 클래스를 포함하지 않으므로 그대로 전달
    num_anchors = model.head.classification_head.num_anchors
    in_channels = model.backbone.out_channels
    model.head = RetinaNetHead(
        in_channels=in_channels,
        num_anchors=num_anchors,
        num_classes=num_classes,
    )

    return model
