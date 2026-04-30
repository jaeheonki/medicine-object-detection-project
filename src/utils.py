# %% 구글 공유 데이터 다운로드
def download_data(extract_path="./data"):
    import zipfile
    from huggingface_hub import hf_hub_download
    from pathlib import Path

    print("데이터 다운로드 중...")
    zip_path = hf_hub_download(
        repo_id="Jaeheonki/pills_extra_data",
        filename="알약데이터.zip",
        repo_type="dataset",
        local_dir="/content"
    )

    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(extract_path)

    print("데이터 다운로드 완료!")

def extract_extra_data(label_out_dir, image_out_dir):
    """
    HuggingFace 데이터셋에서 추가 학습 데이터를 다운로드해 지정 경로에 저장한다.

    데이터 구조: tar → zip.part 분할 파일 → 이미지/JSON
    처리 순서: tar 다운로드 → tar 해제 → zip.part 합치기 → 파일 추출 → 복사

    Args:
        label_out_dir: JSON 라벨 파일을 저장할 경로
        image_out_dir: 이미지 파일을 저장할 경로
    """
    import subprocess, zipfile, shutil
    from pathlib import Path
    from huggingface_hub import hf_hub_download, list_repo_files

    REPO_ID = "Jaeheonki/pills_extra_data"
    tmp_dir = Path('/content/_extra_tmp')

    # repo 파일 목록을 한 번만 가져와 이미지/라벨 처리에 공유
    all_files = list(list_repo_files(REPO_ID, repo_type="dataset"))

    def process_folder(out_dir, file_exts, folder_name):
        """tar 파일 목록을 받아 압축 해제 후 대상 경로에 파일을 복사한다."""
        tmp_dir.mkdir(exist_ok=True)

        # repo 전체 목록에서 해당 폴더의 tar 파일만 필터링
        tar_files = [f for f in all_files if f.startswith(folder_name) and f.endswith('.tar')]
        print(f'[1/4] tar 파일 {len(tar_files)}개 발견')

        try:
            for tar_file in tar_files:
                print(f'[1/4] 다운로드 중: {tar_file}')
                # HuggingFace에서 tar 파일 하나씩 다운로드
                tar_path = Path(hf_hub_download(
                    repo_id=REPO_ID,
                    filename=tar_file,
                    repo_type="dataset",
                    local_dir=str(tmp_dir)
                ))

                # tar 파일명(확장자 제외)을 추출 디렉토리명으로 사용
                extract_dir = tmp_dir / tar_path.stem
                extract_dir.mkdir(exist_ok=True)

                try:
                    # [2/4] tar 해제
                    try:
                        print(f'[2/4] tar 해제 중: {tar_path.name}')
                        subprocess.run(['tar', '-xf', str(tar_path), '-C', str(extract_dir)], check=True)
                    except subprocess.CalledProcessError as e:
                        print(f'tar 해제 실패, 건너뜀: {tar_path.name} — {e}')
                        continue

                    # [3/4] zip.part 분할 파일을 숫자 순서로 정렬 후 하나의 zip으로 합치기
                    print(f'[3/4] zip.part 합치기: {tar_path.name}')
                    parts = sorted(
                        [p for p in extract_dir.rglob('*') if '.part' in p.name],
                        key=lambda p: int(p.name.split('.part')[-1])
                    )
                    if not parts:
                        print(f'zip.part 파일 없음, 건너뜀: {tar_path.name}')
                        continue

                    zip_path = extract_dir / 'combined.zip'
                    with open(zip_path, 'wb') as outfile:
                        for part in parts:
                            with open(part, 'rb') as f:
                                outfile.write(f.read())

                    # [4/4] zip에서 대상 확장자 파일만 out_dir로 복사
                    print(f'[4/4] 파일 추출 중: {tar_path.name}')
                    unzip_dir = extract_dir / 'unzipped'
                    with zipfile.ZipFile(zip_path, 'r') as z:
                        for name in z.namelist():
                            if Path(name).suffix.lower() in file_exts:
                                z.extract(name, unzip_dir)

                    for f in unzip_dir.rglob('*'):
                        if f.is_file():
                            shutil.copy2(f, Path(out_dir) / f.name)

                    print(f'{tar_path.name} 완료')

                finally:
                    # tar 하나 처리 완료 후 즉시 삭제해 디스크 공간 확보
                    tar_path.unlink(missing_ok=True)
                    shutil.rmtree(extract_dir, ignore_errors=True)

        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    process_folder(image_out_dir, {'.jpg', '.jpeg', '.png', '.bmp'}, "이미지")
    process_folder(label_out_dir, {'.json'}, "라벨")

    print('추가 데이터 처리 완료!')

def download_more_data(label_out_dir, image_out_dir):
    import gdown, zipfile, shutil
    from pathlib import Path

    zip_path = Path("./more_data.zip")
    temp_dir = Path("./temp_download")

    gdown.download(f"https://drive.google.com/uc?id=1gq3W2g0GbOna9wd3kImSqXetBBLeLs-i", str(zip_path), quiet=False)
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(temp_dir)

    src_folder = list(temp_dir.iterdir())[0]
    for file in (src_folder / "images").iterdir():
        shutil.move(str(file), str(Path(image_out_dir) / file.name))
    for file in (src_folder / "labels").iterdir():
        shutil.move(str(file), str(Path(label_out_dir) / file.name))

    zip_path.unlink()
    shutil.rmtree(temp_dir)
    print("추가 데이터 다운로드 완료!")
