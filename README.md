# 이게머약 💊 — 알약 인식 및 정보 조회 앱

스마트폰으로 알약을 촬영하면 YOLO 모델이 약을 인식하고, 식약처 API를 통해 효능·복용법·주의사항을 조회해주는 모바일 앱입니다.

---

## 팀원

| 이름 | 역할 |
|------|------|
|김재헌 | |
|김건오 | |
|김재헌 | |
|임유빈 | |

---

## 주요 기능

- **알약 인식** — 촬영 또는 갤러리 이미지로 알약 탐지
- **약 정보 조회** — 효능, 복용법, 주의사항 자동 조회
- **복약 알림** — 복약 시간 설정 및 알림 등록
- **약 목록** — 인식 가능한 전체 약품 목록 조회

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| 모바일 앱 | ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white) |
| 서버 | ![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white) ![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white) ![Uvicorn](https://img.shields.io/badge/Uvicorn-4751B5?style=for-the-badge&logo=uvicorn&logoColor=white) |
| AI 모델 | ![YOLO](https://img.shields.io/badge/YOLOv11s-00FFFF?style=for-the-badge&logo=yolo&logoColor=black) |
| 약 정보 API | 식약처 제품허가정보 API, e약은요 API |
| 의존성 관리 | ![uv](https://img.shields.io/badge/uv-DE5FE9?style=for-the-badge&logo=uv&logoColor=white) |

---

## 모델 성능

| 지표 | 값 |
|------|----|
| mAP@0.5 | 0.9914 |
| mAP@0.75:0.95 | 0.9811 |
| F1 Score | 0.9948 |

> 모델 선정 과정 및 실험 결과는 [docs/](docs/)를 참고하세요.

---

## 파이프라인

```
[Flutter 앱]
    │
    │  이미지 선택 → POST /predict
    ▼
[FastAPI 서버]
    │
    ├─ YOLO 추론 → 알약 탐지 + bbox crop
    ├─ 식약처 API 조회 (병렬)
    └─ JSON 응답 반환
    │
    ▼
[Flutter 앱]
    탐지 결과 카드 표시 + 복약 알림 등록
```

---

## 실행 방법

### 서버 실행 (PC)

```bash
# 의존성 설치
uv sync

# .env 설정 (.env.example 참고)
cp .env.example .env

# 서버 실행
uvicorn src.pill_lookup_api:app --host 0.0.0.0 --port 9000
```

### 앱 빌드 (Android APK)

```bash
cd pill_app
flutter pub get
flutter build apk
```

> `lib/screens/home_screen.dart`, `lib/screens/pill_list_screen.dart`의 서버 URL을 PC의 IP 주소로 변경 후 빌드하세요.
> 빌드된 APK는 `build/app/outputs/flutter-apk/app-release.apk`에 생성됩니다.

---

## 폴더 구조

```
Medicine_Project/
├── checkpoints/        # YOLO 모델 가중치
├── data/               # 학습 데이터
├── docs/               # EDA 분석, 도메인 지식 문서
├── models/             # 모델 아키텍처 코드
├── pill_app/           # Flutter 앱
├── src/                # FastAPI 서버, 데이터 처리 코드
└── tests/              # 테스트 코드
```

---

