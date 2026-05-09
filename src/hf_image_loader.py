from huggingface_hub import list_repo_files, hf_hub_download
from pathlib import Path
from PIL import Image

# 이미지 파일 경로 리스트 불러오기
def list_image_files(repo_id, folder_path):
    all_files = list_repo_files(repo_id, repo_type = "dataset")

    image_extensions = [".jpg",".png",".jfif"]

    image_files = []
    for file in all_files:
        is_in_folder = file.startswith(folder_path + "/")
        is_image = Path(file).suffix.lower() in image_extensions

        if is_in_folder and is_image:
            image_files.append(file)

    return image_files

'''
확인용 코드
print(files[:5])
'''

# 이미지 다운로드
def download_image(repo_id, file_path):
    local_path = hf_hub_download(
        repo_id = repo_id,
        filename = file_path,
        repo_type = "dataset"
    )

    image = Image.open(local_path)

    return image

'''
확인용 코드
first_file = files[0]
image = download_image(repo_id, first_file)

print(image.size)
print(image.mode)
image.show()
'''

# 여러 장을 data/pill_images에 저장하기 (경로 임의 설정)
def save_images(repo_id, folder_path, output_dir, limit = None):
    files = list_image_files(repo_id, folder_path)

    if limit is None:
        selected_files = files
    else:
        selected_files = files[:limit]

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok = True)

    saved_paths = []

    for file in selected_files:
        image = download_image(repo_id, file)

        file_name = Path(file).name
        save_path = output_dir / file_name

        image.save(save_path)
        saved_paths.append(save_path)

    return  saved_paths


if __name__ == "__main__":
    repo_id = "Jaeheonki/pills_extra_data"
    folder_path = "약 사진"

    saved_paths = save_images(
        repo_id,
        folder_path,
        output_dir = "data/pill_images", #제가 임의로 설정해둔 경로입니다. 이미지가 저장될 실제 경로로 수정 필요
        limit = None
    )

    print(saved_paths)