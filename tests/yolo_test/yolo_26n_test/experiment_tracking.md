---

## (1차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 100 |
| Optimizer      | AdamW |
| LR             | 0.01 |
| Augmentation   | 적용 |
| 기타 설정        | 없음 |
| 비고            | 이미지 크기 증가 + batch 증가 + augmentation 적용하여 성능 변화 확인 |
| Best mAP@0.5        | 0.6294 (epoch 98) |
| Best mAP@0.75:0.95        | 0.5747 (epoch 100) |
| Best F1 Score        | 0.7396 (epoch 100) |
| 총 학습 시간        | 19분 13초 |

---

## (2차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 100 |
| Optimizer      | AdamW |
| LR             | 0.01 |
| Augmentation   | 없음 |
| 기타 설정        | imgsz만 증가 |
| 비고            | 이미지 크기 증가만 단독으로 적용하여 영향 분석 |
| Best mAP@0.5        | 0.7415 (epoch 95) |
| Best mAP@0.75:0.95        | 0.7094 (epoch 97) |
| Best F1 Score        | 0.7634 (epoch 91) |
| 총 학습 시간        | 19분 31초 |

---

## (3차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 100 |
| Optimizer      | AdamW |
| LR             | 0.01 |
| Augmentation   | 약한 색상 증강 |
| 기타 설정        | hsv 기반 |
| 비고            | 강한 augmentation 대신 약한 색상 변화만 적용하여 성능 확인 |
| Best mAP@0.5        | 0.7828 (epoch 83) |
| Best mAP@0.75:0.95        | 0.7505 (epoch 80) |
| Best F1 Score        | 0.8028 (epoch 97) |
| 총 학습 시간        | 18분 55초 |

---

## (4차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 120 |
| Optimizer      | AdamW |
| LR             | 0.01 |
| Augmentation   | 기존 유지 |
| 기타 설정        | 없음 |
| 비고            | epoch 증가를 통해 성능 향상 여부 확인 |
| Best mAP@0.5        | 0.8282 (epoch 94) |
| Best mAP@0.75:0.95        | 0.7999 (epoch 95) |
| Best F1 Score        | 0.8000 (epoch 105) |
| 총 학습 시간        | 22분 25초 |

---

## (5차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 120 |
| Optimizer      | AdamW |
| LR             | 0.005 |
| Augmentation   | 기존 유지 |
| 기타 설정        | 없음 |
| 비고            | learning rate 감소를 통해 미세 조정 |
| Best mAP@0.5        | 0.8282 (epoch 94) |
| Best mAP@0.75:0.95        | 0.7999 (epoch 95) |
| Best F1 Score        | 0.8000 (epoch 105) |
| 총 학습 시간        | 23분 19초 |

---

## (6차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 120 |
| Optimizer      | SGD |
| LR             | 0.005 |
| Augmentation   | 기존 유지 |
| 기타 설정        | optimizer 수동 고정 |
| 비고            | YOLO 내부 LR 스케줄 무시 문제로 optimizer 직접 제어. AdamW는 빠르게 수렴하지만 미세 구분이 약함 → SGD는 느리지만 안정적이고 더 넓은 탐색 가능 |
| Best mAP@0.5        | 0.9161 (epoch 102) |
| Best mAP@0.75:0.95        | 0.8823 (epoch 102) |
| Best F1 Score        | 0.8803 (epoch 92) |
| 총 학습 시간        | 23분 2초 |

---

## (7차 튜닝)

| 항목            | 값 |
|----------------|-----|
| 모델            | yolo26s |
| 이미지 크기      | 768 |
| 배치            | 16 |
| Epochs         | 120 |
| Optimizer      | SGD |
| LR             | 0.003 |
| Augmentation   | 기존 유지 |
| 기타 설정        | 없음 |
| 비고            | 6차 튜닝 기반에서 learning rate 추가 감소로 미세 조정 |
| Best mAP@0.5        | 0.8346 (epoch 115) |
| Best mAP@0.75:0.95        | 0.8064 (epoch 115) |
| Best F1 Score        | 0.8183 (epoch 108) |
| 총 학습 시간        | 22분 51초 |

---

## 최종 결론

- 가장 성능이 좋은 모델: **(6차 튜닝)**
- AdamW 대비 SGD가 더 안정적인 학습 및 성능 향상에 기여
- learning rate를 직접 제어하는 것이 성능 개선에 중요한 요소였음