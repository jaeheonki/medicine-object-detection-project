# YOLO26s 실험 추적표

## 실험 1

| 항목            | 값 |
|----------------|-----|
| 모델            |  yolo26s   |
| 이미지 크기      |  640   |
| 배치            |  16   |
| Epochs         |   100  |
| Optimizer      |  AdamW   |
| LR             |  0.001   |
| WD             |  0.0005   |
| Momentum       |  0.9   |
| Augmentation   |   X  |
| 기타 설정        |  기본   |
| mAP@0.5        |   0.9739  (Epoch 86)  |
| mAP@0.75:0.95  |  0.9139  (Epoch 100)   |
| F1             |  0.9666 (epoch 97)   |
| 학습 시간        |   42분 32초  |
| 비고            |  추가 데이터 증강 후 baseline 학습 진행 |

---

## 실험 2

| 항목            | 값 |
|----------------|-----|
| 모델            |   yolo26s  |
| 이미지 크기      |   640  |
| 배치            |  16   |
| Epochs         |   120  |
| Optimizer      |  AdamW   |
| LR             |  0.001  |
| WD             |  0.0005   |
| Momentum       |   0.9  |
| Augmentation   |   hsv_h = 0.015,
hsv_s = 0.5,
hsv_v = 0.5,
degrees = 0.0,
translate = 0.05,
scale = 0.1,
shear = 0.0,
perspective = 0.0,
flipud = 0.5,
fliplr = 0.5,
mosaic = 0.0,
close_mosaic = 0,
mixup = 0.0,
copy_paste = 0.0  |
| 기타 설정        |   기본  |
| mAP@0.5        |  0.9456 (epoch 58)   |
| mAP@0.75:0.95  |  0.8609 (epoch 84)  |
| F1             |  0.9545 (epoch 99) |
| 학습 시간        |  42분 57초   |
| 비고            |   augmentation 추가했지만 기존 baseline 성능이 더 좋게 나옴. 알약데이터는 방향성이 중요할 수 있어서 augmentation이 오히려 성능 저하 유발 |

---

## 실험 3

| 항목            | 값 |
|----------------|-----|
| 모델            |  yolo26s   |
| 이미지 크기      |   640  |
| 배치            |  16   |
| Epochs         |  150   |
| Optimizer      |  AdamW   |
| LR             |  0.001   |
| WD             |   0.0005  |
| Momentum       |   0.9  |
| Augmentation   |   X  |
| 기타 설정        |   기본  |
| mAP@0.5        |  0.9723 (epoch 113)   |
| mAP@0.75:0.95  |  0.9418 (epoch 139)  |
| F1             |  0.9765 (epoch 128)  |
| 학습 시간        |  59분 49초   |
| 비고            |  baseline에 epoch만 150으로 늘렸음. 성능지표가 지금까지 가장 좋았음 |

---
