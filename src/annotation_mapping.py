from pathlib import Path
from collections import defaultdict
import json
import pandas as pd


# 1. 경로 설정
PROJECT_ROOT = Path("/content/알약데이터").resolve()  # '알약데이터'는 압축을 푼 폴더명
DATA_ROOT = PROJECT_ROOT / "sprint_ai_project1_data"
TRAIN_ANN_DIR = DATA_ROOT / "train_annotations"
OUTPUT_DIR = (
    PROJECT_ROOT / "merged_annotations"
)  # data 폴더 내에 merged_annotations라는 폴더를 새로 생성하고 그 폴더에 json 파일을 할당

print("PROJECT_ROOT:", PROJECT_ROOT)
print("TRAIN_ANN_DIR:", TRAIN_ANN_DIR)
print("OUTPUT_DIR:", OUTPUT_DIR)


# 2. 원본 JSON 1개 파싱
# parse_annotation_file 함수는 json파일의 경로 하나를 입력으로 받아 정보를 parsed_data 딕셔너리에 저장하고 parsed_data 딕셔너리를 리턴해주는 함수
def parse_annotation_file(json_path):
    json_path = Path(json_path)  # json 파일의 경로를 json_path에 할당

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)  # data 변수에 json파일의 정보들을 할당

    if "images" not in data or len(data["images"]) == 0:
        raise ValueError(f"'images'가 없거나 비어 있습니다: {json_path}")

    # data의 구조는 "imgaes"키 (리스트 -> 딕셔너리) 구조
    image_info = data["images"][
        0
    ]  # image_info 변수에 json파일의 이미지 정보들을 딕셔너리로 할당

    parsed_data = {
        # 파일 자체 정보
        "json_path": str(json_path),
        "json_name": json_path.name,
        "json_stem": json_path.stem,
        # 이미지 식별 정보
        "file_name": image_info.get("file_name"),
        "width": image_info.get("width"),
        "height": image_info.get("height"),
        "image_id": image_info.get("id"),
        # 원본 전체 보존
        "raw_data": data,
        "raw_image": image_info,
        "raw_annotations": data.get(
            "annotations", []
        ),  # annotation이 없는 경우에 빈 리스트를 할당
        "raw_categories": data.get(
            "categories", []
        ),  # categories가 없는 경우에 빈 리스트를 할당
    }

    return parsed_data


# 3. 여러 JSON 파싱
# 어노테이션 파일이 모여있는 폴더 경로 (현재 데이터셋의 경우 train_annotations)를 입력받아 json파일들의 경로를 모으고 parse_annotation_file함수를 통해 복사된 json 파일의 값들을 parsed_list에 모아 parsed_list와 failed_files를 리턴해주는 함수
# 이때 failed-files는 json_path가 없거나 잘못된 경우 들어가는 리스트
def parse_all_annotation_files(
    annotation_root_dir,
):  # 어노테이션 파일이 모여있는 경로를 입력받음, 현재 데이터셋의 경우 train_annotaions 폴더까지의 경로를 입력으로 받아야함
    annotation_root_dir = Path(annotation_root_dir)
    json_paths = sorted(
        annotation_root_dir.rglob("*.json")
    )  # train_annotations 내의 하위 모든 폴더를 탐색하여 json파일의 경로만 추출, 이후 json_paths 변수에 리스트 형태로 저장

    parsed_list = []  # json파일을 복사한 parse_annotation_file함수의 결과값(딕셔너리)가 들어갈 리스트
    failed_files = []

    for json_path in json_paths:
        try:
            parsed = parse_annotation_file(json_path)
            parsed_list.append(parsed)
        except Exception as e:
            failed_files.append({"json_path": str(json_path), "error": str(e)})

    return parsed_list, failed_files


# 4. bbox xywh -> xyxy 변환
def xywh_to_xyxy(bbox_xywh):
    x, y, w, h = bbox_xywh
    return [x, y, x + w, y + h]


# 5. 같은 이미지(file_name)끼리 병합
#    - 원본 annotation, category, image 정보 보존
# 최종적으로 json 파일의 복사값이 모여있는 딕셔너리(parsed_list)를 받아 이미지 하나당 여러 객체의 정보가 담긴 딕셔너리를 리턴
def merge_annotations_by_image(
    parsed_list,
):  # parse_all_annotation_files함수의 리턴값을 인자로 받음(json파일의 복사값이 모여있는 딕셔너리)
    grouped = defaultdict(
        list
    )  # 이미지 파일 하나를 키로, 이미지 파일에 담겨야하는 json파일들을 키로 저장하는 딕셔너리 생성

    for item in parsed_list:
        file_name = item["file_name"]  # 여기서 item은 json파일의 정보를 담은 딕셔너리
        grouped[file_name].append(
            item
        )  # json 파일이 가르키는 이미지가 동일한 json 파일들끼리 묶는 작업을 수행

    merged_results = []

    for (
        file_name,
        items,
    ) in grouped.items():  # file_name은 파일 이름(이미지 이름) items는 이미지 이름을 가르키는 json파일들이 모인 리스트
        first = items[0]

        merged_item = {  # 최종적으로 만든 어노테이션의 뼈대, 즉 최 상위 key 값들
            "file_name": file_name,  # 파일 이름
            "width": first["width"],  # 너비
            "height": first["height"],  # 높이
            # 어떤 원본 JSON들에서 합쳐졌는지 보존
            "source_files": [item["json_path"] for item in items],
            # 원본 image 정보 전체 보존
            # 가공 전 각 json파일이 가졌던 images를 리스트 형태로 raw_images 변수에 저장
            "raw_images": [item["raw_image"] for item in items],
            # category 원본 보존
            "raw_categories": [],
            # 최종 병합 annotation
            "merged_annotations": [],
        }

        seen_category_keys = set()

        for item in items:  # 가공 전의 json 파일에서 item으로 하나 꺼내기
            # categories 중복 제거하며 보존
            for cat in item["raw_categories"]:
                cat_key = (cat.get("id"), cat.get("name"), cat.get("supercategory"))
                if cat_key not in seen_category_keys:
                    merged_item["raw_categories"].append(cat)
                    seen_category_keys.add(cat_key)

            # annotations 병합
            for ann in item["raw_annotations"]:
                bbox_xywh = ann.get("bbox", None)

                merged_ann = {"source_json": item["json_path"], "raw_annotation": ann}

                if bbox_xywh is not None and len(bbox_xywh) == 4:
                    merged_ann["bbox_xywh"] = bbox_xywh
                    merged_ann["bbox_xyxy"] = xywh_to_xyxy(bbox_xywh)
                else:
                    merged_ann["bbox_xywh"] = None
                    merged_ann["bbox_xyxy"] = None

                merged_item["merged_annotations"].append(merged_ann)

        merged_item["num_source_files"] = len(items)
        merged_item["num_annotations"] = len(merged_item["merged_annotations"])

        merged_results.append(merged_item)

    return merged_results


# 6. 병합 결과 저장
#    - 이미지 1장당 JSON 1개
def save_merged_annotations(
    merged_results, output_dir
):  # 위에서 만든 최종 어노테이션 형태와 그 어노테이션을 저장할 위치를 입력값으로 받음
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)  # 폴더 생성

    saved_paths = []

    for item in merged_results:
        file_name = item["file_name"]
        stem = Path(file_name).stem
        output_path = output_dir / f"{stem}.json"

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(item, f, ensure_ascii=False, indent=4)

        saved_paths.append(str(output_path))

    return saved_paths


# 7. 병합 결과 요약표 생성
def build_merge_summary_df(merged_results):
    rows = []

    for item in merged_results:
        rows.append(
            {
                "file_name": item["file_name"],
                "width": item["width"],
                "height": item["height"],
                "num_source_files": item["num_source_files"],
                "num_annotations": item["num_annotations"],
            }
        )

    return pd.DataFrame(rows)


# 실제 import 해서 실행할 함수
def run_annotation_mapping(
    annotation_root_dir, output_dir
):  # train_annotation의 경로와 merged_annotaion을 저장할 폴더 경로를 입력해주면 됨
    annotation_root_dir = Path(annotation_root_dir)
    output_dir = Path(output_dir)

    parsed_list, failed_files = parse_all_annotation_files(annotation_root_dir)
    merged_results = merge_annotations_by_image(parsed_list)
    saved_paths = save_merged_annotations(merged_results, output_dir)
    merge_summary_df = build_merge_summary_df(merged_results)

    return {
        "parsed_list": parsed_list,
        "failed_files": failed_files,
        "merged_results": merged_results,
        "saved_paths": saved_paths,
        "merge_summary_df": merge_summary_df,
    }


# 8. 전체 실행
def main():
    parsed_list, failed_files = parse_all_annotation_files(TRAIN_ANN_DIR)

    print("파싱 성공 JSON 수:", len(parsed_list))
    print("파싱 실패 JSON 수:", len(failed_files))

    if len(failed_files) > 0:
        failed_df = pd.DataFrame(failed_files)
        print(failed_df.head())

    merged_results = merge_annotations_by_image(parsed_list)

    print("병합 후 이미지 수:", len(merged_results))

    saved_paths = save_merged_annotations(merged_results, OUTPUT_DIR)

    print("저장된 merged annotation 수:", len(saved_paths))
    print("저장 샘플 5개:")
    for p in saved_paths[:5]:
        print(p)

    merge_summary_df = build_merge_summary_df(merged_results)
    print(merge_summary_df.head())


if __name__ == "__main__":
    main()
