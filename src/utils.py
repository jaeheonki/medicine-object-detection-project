# %% 구글 공유 데이터 다운로드
def download_data(extract_path="./data"):
    import gdown, zipfile
    gdown.download(f"https://drive.google.com/uc?id=1YgTmJPuppvarVklbkxAO7SK11fI-Siim", "알약데이터.zip", quiet=False)
    with zipfile.ZipFile("알약데이터.zip", "r") as zip_ref:
        zip_ref.extractall(extract_path)
    print("데이터 다운로드 완료!")

def extract_extra_data(label_out_dir, image_out_dir):
    """
    구글 드라이브 공유 폴더에서 추가 데이터 tar 파일을 다운로드 후 압축 해제해서
    이미지는 image_out_dir, JSON 라벨은 label_out_dir에 넣는다.

    tar 안에 zip.part 분할 파일이 있으므로 아래 순서로 처리한다:
    1. gdown으로 폴더 전체 다운로드
    2. tar 해제 → zip.part 파일 추출
    3. zip.part 파일을 offset 순으로 합쳐 하나의 zip으로 결합
    4. zip에서 대상 파일(이미지 or JSON)만 추출해 out_dir로 복사
    5. 임시 폴더 삭제 후 다음 tar 처리
    """
    import gdown, subprocess, zipfile, shutil
    from pathlib import Path

    RAW_FOLDER_ID = 'https://drive.google.com/drive/folders/13odlbFQ7AhuYnR43mKmR1tmgSRn73Wy8'    # 원천 데이터(이미지) tar 파일 폴더 ID — 발급 후 채워넣기
    LABEL_FOLDER_ID = 'https://drive.google.com/drive/folders/1sN2l7K7rhWyqz7GW-Ji1-ROwBI-Q8I73'  # 라벨 데이터(JSON) tar 파일 폴더 ID — 발급 후 채워넣기

    tmp_dir = Path('/content/_extra_tmp')

    def process_folder(folder_id, out_dir, file_exts):
        tmp_dir.mkdir(exist_ok=True)
        try:
            print(f'[1/4] 폴더 다운로드 중 ...')
            gdown.download_folder(url=folder_id, output=str(tmp_dir), quiet=False)

            tar_paths = sorted(tmp_dir.rglob('*.tar'))
            for tar_path in tar_paths:
                extract_dir = tmp_dir / tar_path.stem
                extract_dir.mkdir(exist_ok=True)
                try:
                    try:
                        print(f'[2/4] tar 해제 중: {tar_path.name}')
                        subprocess.run(['tar', '-xf', str(tar_path), '-C', str(extract_dir)], check=True)
                    except subprocess.CalledProcessError as e:
                        print(f'tar 해제 실패, 건너뜀: {tar_path.name} — {e}')
                        continue

                    # zip.part 파일을 offset(숫자 suffix) 기준으로 정렬 후 합치기
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

                    # zip에서 대상 확장자 파일만 out_dir로 추출
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
                    # tar 하나 처리 완료 후 즉시 extract_dir 삭제해 디스크 공간 확보
                    shutil.rmtree(extract_dir, ignore_errors=True)
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    process_folder(RAW_FOLDER_ID, image_out_dir, {'.jpg', '.jpeg', '.png', '.bmp'})
    process_folder(LABEL_FOLDER_ID, label_out_dir, {'.json'})

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
